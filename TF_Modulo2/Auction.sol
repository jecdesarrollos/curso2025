// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Auction
 * @dev This contract implements an auction system where
 * bidders can place incremental bids.
 * It includes functionalities to manage the auction's state, bidder deposits,
 * time extensions for late bids, and fund distribution (winner's bid, refunds, commissions).
 * The final fund distribution is handled by the owner as a specific project requirement.
 * @author Jorge Enrique Cabrera [Trabajo Practico Modulo 2 TALENTO TECH PM]
 * @custom:github https://github.com/jecdesarrollos/curso2025
 */

contract Auction {
    // --- CONSTANTS ---
    /**
     * @dev Minimum percentage increment a new bid must have compared to the previous one.
     * Example: If the current bid is 100, the next one must be at least 105 (100 + 5%).
     */
    uint256 public constant MIN_BID_INCREMENT_PERCENTAGE = 5;

    /**
     * @dev Original duration of the auction in seconds.
     * Once the auction is activated, this time is added to `auctionStartTime` to define `auctionEndTime`.
     */
    uint256 private constant INITIAL_AUCTION_DURATION = 172800; // 60*60*24*2 = 48 horas

    /**
     * @dev Time in seconds by which the auction is extended if a bid is received
     * very close to `auctionEndTime`; in this case, the same proposed extension time is used.
     */
    uint256 public constant AUCTION_EXTENSION_TIME = 600; // 60*10 = 10 minutos

    /**
     * @dev Commission percentage deducted from the deposit of non-winning bidders
     * when they claim their refund, or when the owner distributes excess funds.
     */
    uint256 public constant COMMISSION_PERCENTAGE = 2;

    // --- ENUMS ---
    /**
     * @dev States in which the auction can be found.
     * - `Pending`: Initial state.
     * - `Active`: When the owner activates it with startAuction, the auction begins and bids are accepted.
     * - `Ended`: The auction time `auctionEndTime` (extended or not) has finished.
     * - `Finalized`: The auction has been finalized by the owner, and the fund distribution phase (refunds, owner withdrawals) begins or in process until completion.
     */
    enum AuctionState {
        Pending,
        Active,
        Ended,
        Finalized
    }

    // --- STRUCTS ---
    /**
     * @dev struct to store info of each bidder.
     * @param bidderAddress address of the bidder.
     * @param totalDeposited The total amount of ether this bidder has deposited in the contract.
     * @param lastBidAmount Amount of this bidder's last accepted bid.
     */
    struct Bidder {
        address bidderAddress;
        uint256 totalDeposited;
        uint256 lastBidAmount;
    }

    /**
     * @dev struct to record each individual bid in the bid history.
     * Note: This history is for didactic purposes because recording
     * all bids consumes a lot of gas and should be done off-chain/logs by observing events.
     * @param bidder The bidder's address.
     * @param amount Amount of the bid.
     * @param timestamp Timestamp of the bid.
     */
    struct AuctionBid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    /**
     * @dev Array to keep the history of all bids made in the auction.
     * For didactic purposes.
     */
    AuctionBid[] public bidsHistory;

    // --- STATE VARIABLES ---
    /**
     * @dev Current state of the auction, defined by the `AuctionState` enum.
     */
    AuctionState public currentAuctionState;

    /**
     * @dev Address of the contract owner.
     * The owner initiates and finalizes the auction. Then withdraws the winning amount as well as commissions.
     */
    address private immutable owner;

    /**
     * @dev Flag indicating whether the winning bid amount has already been transferred to the owner.
     * To prevent double withdrawal.
     */
    bool public flagWinnerFundsWithdrawn;

    /**
     * @dev The timestamp of the block when the auction was started.
     */
    uint256 public auctionStartTime;

    /**
     * @dev The timestamp when the auction will end.
     * Calculated by adding `INITIAL_AUCTION_DURATION` to `auctionStartTime`, and can be extended
     * by `AUCTION_EXTENSION_TIME` if there are bids before it ends.
     */
    uint256 public auctionEndTime;

    /**
     * @dev Address of the bidder who has made the highest bid so far,
     * and who will be the winner if the auction ends without another surpassing bid.
     */
    address public currentWinner;

    /**
     * @dev Amount of the highest accepted bid.
     * Initialized with the minimum bid in the constructor.
     */
    uint256 public highestBid;

    /**
     * @dev Total amount of commissions (2% percentage of refunds to losers) collected
     * by the contract, which the `owner` can withdraw.
     */
    uint256 public totalCommissionsCollected;

    /**
     * @dev Mapping that associates a bidder's address with their corresponding `Bidder` structure,
     * storing their deposits and last accepted bid.
     */
    mapping(address => Bidder) public bidders;

    /**
     * @dev Array to keep track of all unique bidder addresses.
     * This allows iterating over all bidders for tasks like refunding.
     */
    address[] public allBidderAddresses;

    /**
     * @dev Mapping to check if an address has already been added to `allBidderAddresses`.
     */
    mapping(address => bool) private hasBidderAddressBeenRecorded;

    // --- MODIFIERS ---
    /**
     * @dev Modifier that restricts the execution of a function only to the contract `owner`.
     * This modifier executes beforehand.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner.");
        _;
    }

    /**
     * @dev Modifier that updates the auction state from `Active` to `Ended`
     * if the `block.timestamp` is >= `auctionEndTime` and the auction was active.
     * This modifier executes before the function.
     */
    modifier updateAuctionState() {
        if (
            currentAuctionState == AuctionState.Active &&
            block.timestamp >= auctionEndTime
        ) {
            currentAuctionState = AuctionState.Ended;
        }
        _;
    }

    // --- EVENTS ---
    /**
     * @dev Event emitted when the auction is activated by the `owner`.
     * @param owner address of the `owner` who activates the auction.
     * @param TimeStart The timestamp when the auction started.
     * @param TimeDuration The original duration of the auction in seconds.
     * @param reason Description.
     */
    event AuctionStart(
        address indexed owner,
        uint256 TimeStart,
        uint256 TimeDuration,
        string reason
    );

    /**
     * @dev Event emitted when a bid is accepted and processed.
     * @param bidder address of the bidder who made the bid.
     * @param amount Amount of the accepted bid.
     * @param reason Description.
     */
    event AuctionBidAccepted(
        address indexed bidder,
        uint256 amount,
        string reason
    );

    /**
     * @dev Event emitted when a bid is rejected for not meeting the requirements.
     * @param bidder address of the bidder who attempted the bid.
     * @param amount Amount of the attempted bid.
     * @param reason Reason for rejection.
     */
    event AuctionBidRejected(
        address indexed bidder,
        uint256 amount,
        string reason
    );

    /**
     * @dev Event emitted when the auction time is extended.
     * This occurs if the bid is placed within `AUCTION_EXTENSION_TIME` before the end.
     * @param bidder address of the bidder whose bid caused the extension.
     * @param amount Bid amount.
     * @param reason Description.
     * @param extendedTime Amount of seconds of the extension.
     */
    event AuctionEndTimeExtended(
        address indexed bidder,
        uint256 amount,
        string reason,
        uint256 extendedTime
    );

    /**
     * @dev Event emitted when a bidder withdraws excess deposits they made during the auction.
     * @param bidder address of the bidder who withdrew the excess deposit.
     * @param amount Amount of ether withdrawn.
     */
    event ExcessDepositWithdrawn(address indexed bidder, uint256 amount);

    /**
     * @dev Event emitted when the auction transitions to the `Finalized` state.
     * @param winner address of the auction winner.
     * @param amount Amount of the winning bid.
     */
    event AuctionEnded(address indexed winner, uint256 amount);

    /**
     * @dev Event emitted when the owner forces the auction to finalize the process just for didactical purposes
     */
    event AuctionEndedbyForce(address indexed winner, uint256 amount);

    /**
     * @dev Event emitted when a non-winning bidder's refund is issued,
     * or when the owner distributes the winner's excess funds.
     * @param bidder address of the recipient.
     * @param amount Amount refunded (minus 2% commission).
     * @param commissionsCollected Amount of the commission.
     */
    event RefundIssued(
        address indexed bidder,
        uint256 amount,
        uint256 commissionsCollected
    );

    /**
     * @dev Event emitted by the owner after all remaining funds have been distributed.
     * @param distributor The address of the owner who distributed the funds.
     * @param totalCommissionsAccruedInThisDistribution The total commissions collected during this specific distribution call.
     * @param timestamp The timestamp when the distribution was completed.
     */
    event FundsDistributed(
        address indexed distributor,
        uint256 totalCommissionsAccruedInThisDistribution,
        uint256 timestamp
    );

    /**
     * @dev Event emitted when the `owner` withdraws accumulated commissions.
     * @param owner address of the `owner`.
     * @param amount Total amount of commissions withdrawn.
     */
    event CommissionWithdrawn(address indexed owner, uint256 amount);

    /**
     * @dev Event emitted when the `owner` withdraws the winning bid funds.
     * @param owner address of the `owner`.
     * @param amount Amount of the winning bid withdrawn by the `owner`.
     */
    event OwnerHighestBidWithdrawn(address indexed owner, uint256 amount);

    /**
     * @dev Event emitted when the owner withdraws the entire contract balance.
     * @param owner The address of the owner who initiated the withdrawal.
     * @param amount The total amount of Ether withdrawn from the contract's balance.
     */
    event ContractBalanceWithdrawn(address indexed owner, uint256 amount);

    /**
     * @dev Constructor of the contract.
     * Executes only once when the contract is deployed on the blockchain.
     * Initializes the `owner` and sets the initial `highestBid` for the auction.
     */
    constructor() {
        owner = msg.sender;
        currentWinner = address(0); // No winner yet
        highestBid = 1000000 wei; // Initial minimum bid
    }

    /**
     * @notice Activates the auction and starts accepting bids.
     * @dev Can only be called by the `owner` and only if the auction is `Pending`.
     * Sets the auction start and end times.
     */
    function startAuction() external onlyOwner {
        require(
            currentAuctionState == AuctionState.Pending,
            "The auction has already been started."
        );
        currentAuctionState = AuctionState.Active;
        auctionStartTime = block.timestamp;
        auctionEndTime = auctionStartTime + INITIAL_AUCTION_DURATION;

        emit AuctionStart(
            msg.sender,
            auctionStartTime,
            INITIAL_AUCTION_DURATION,
            "The auction has started."
        );
    }

    /**
     * @notice Returns the minimum required amount for the next valid bid.
     * @dev This calculation is based on the current `highestBid` plus the `MIN_BID_INCREMENT_PERCENTAGE`.
     * If there are no previous bids (it's the first bid), it returns the initial `highestBid` without increment.
     * @return uint256 The minimum amount for the next bid.
     */
    function getNextMinimumBidAmount() public view returns (uint256) {
        if (currentWinner == address(0)) {
            // If there's no bid yet, return `highestBid`.
            return highestBid;
        } else {
            // If there's already a previous bid
            return
                highestBid + (highestBid * MIN_BID_INCREMENT_PERCENTAGE) / 100;
        }
    }

    /**
     * @notice Allows participants to bid.
     * @dev A bid is valid if:
     * - The auction is in `Active` state.
     * - The bidder is not the contract `owner`.
     * - The bid amount (`_amount`) is greater than or equal to `requiredMinBid`.
     * - The amount sent (`msg.value`) is sufficient to cover the bid (`_amount`).
     * Updates the highest bid, the current winner, and records the bidder's deposit.
     * Can extend the auction time if the bid is within the last 10 minutes.
     * @param _amount Bid amount.
     */
    function placeBid(uint256 _amount) external payable updateAuctionState {
        // Validation 1: Owner cannot participate
        if (msg.sender == owner) {
            emit AuctionBidRejected(
                msg.sender,
                _amount,
                "Owner cannot participate in the auction."
            );
            revert("Owner cannot participate in the auction.");
        }

        // Validation 2: Auction must to be active
        if (currentAuctionState != AuctionState.Active) {
            emit AuctionBidRejected(
                msg.sender,
                _amount,
                "Auction is not active."
            );
            revert("Auction is not active.");
        }

        // Calculate the minimum for the next bid
        uint256 requiredMinBid = getNextMinimumBidAmount();

        // Validation 3: Bid must meet the minimum requirement
        if (_amount < requiredMinBid) {
            emit AuctionBidRejected(
                msg.sender,
                _amount,
                "Bid does not meet the minimum requirement."
            );
            revert("Bid does not meet the minimum requirement.");
        }

        // Validation 4: Sent Ether must be sufficient for the bid
        if (msg.value < _amount) {
            emit AuctionBidRejected(
                msg.sender,
                _amount,
                "Amount of Ether sent is insufficient for the bid."
            );
            revert("Amount of Ether sent is insufficient for the bid.");
        }

        // Add bidder to allBidderAddresses if it's their first bid
        if (!hasBidderAddressBeenRecorded[msg.sender]) {
            allBidderAddresses.push(msg.sender);
            hasBidderAddressBeenRecorded[msg.sender] = true;
        }

        // Update bidder data
        bidders[msg.sender].bidderAddress = msg.sender;
        bidders[msg.sender].totalDeposited += msg.value;
        bidders[msg.sender].lastBidAmount = _amount;

        // Time extension logic
        if (auctionEndTime - block.timestamp <= AUCTION_EXTENSION_TIME) {
            auctionEndTime += AUCTION_EXTENSION_TIME;
            emit AuctionEndTimeExtended(
                msg.sender,
                _amount,
                "Auction closing has been extended.",
                AUCTION_EXTENSION_TIME
            );
        }

        // Update the highest bid and the current winner
        highestBid = _amount;
        currentWinner = msg.sender;

        // Record the bid in history
        bidsHistory.push(
            AuctionBid({
                bidder: msg.sender,
                amount: _amount,
                timestamp: block.timestamp
            })
        );

        // Emit bid accepted event
        emit AuctionBidAccepted(
            msg.sender,
            _amount,
            "Bid successfully accepted."
        );
    }

    /**
     * @notice Returns the complete history of all bids made in the auction.
     * @dev This function is gas-expensive.
     * @return AuctionBid[] An array of `AuctionBid` structs with all bids.
     */

    function getAllBids() public view returns (AuctionBid[] memory) {
        return bidsHistory;
    }

    /**
     * @notice Returns the current state of the auction.
     * @dev This value is updated by the `updateAuctionState` modifier.
     * It is `Pending` until `startAuction` is called by the `owner`.
     * @return AuctionState The current state of the auction (Pending, Active, Ended, Finalized).
     */
     
    function getCurrentAuctionState() external view returns (AuctionState) {
        return currentAuctionState;
    }

    /**
     * @notice Returns the address of the current bidder with the highest bid and the amount.
     * @dev Can only be called once the auction has ended (`Ended` or `Finalized` state).
     * @return Winner The address of the winning bidder.
     * @return Amount Amount of the winning bid.
     */
    function getWinner() public view returns (address Winner, uint256 Amount) {
        require(
            currentAuctionState == AuctionState.Ended ||
                currentAuctionState == AuctionState.Finalized,
            "The auction is still active."
        );
        return (currentWinner, highestBid);
    }

    /**
     * @notice Allows participants to withdraw any excess deposits.
     * @dev A bidder can withdraw excess if:
     * - The auction is `Active`: withdraws the difference between their `totalDeposited` and their `lastBidAmount`.
     * Once the auction ends, the owner manages all remaining fund transfers.
     */
    function withdrawExcessDeposit() public updateAuctionState {
        require(
            currentAuctionState == AuctionState.Active,
            "Cannot withdraw excess: the auction is not active. Funds are managed by the owner after finalization."
        );

        Bidder storage bidder = bidders[msg.sender];

        require(
            bidder.bidderAddress != address(0),
            "You have not placed any bids in this auction."
        );
        require(
            bidder.totalDeposited > bidder.lastBidAmount,
            "No excess deposit to withdraw."
        );

        uint256 excessAmount = bidder.totalDeposited - bidder.lastBidAmount;

        bidder.totalDeposited = bidder.lastBidAmount; // After withdrawing excess, `totalDeposited` remains at `lastBidAmount`.

        // Perform the transfer of the deposit to the bidder.
        (bool success, ) = payable(msg.sender).call{value: excessAmount}("");
        require(success, "Failed to withdraw excess deposit.");

        // Emit an event to record the excess withdrawal.
        emit ExcessDepositWithdrawn(msg.sender, excessAmount);
    }

    /// @notice Finalizes the auction by the owner, and funds and commissions are processed.
    /// @dev `onlyOwner` only when the auction ends by time.
    /// Once ended, the owner can withdraw commissions and the winner's deposit.
    /// The owner can also distribute refunds to non-winners and the winner's excess deposits.
    function finalizeAuction() public onlyOwner updateAuctionState {
        require(
            currentAuctionState == AuctionState.Ended,
            "The auction has not ended by time or is not in 'Ended' state."
        );

        require(
            currentAuctionState != AuctionState.Finalized,
            "The auction has already been finalized."
        );

        currentAuctionState = AuctionState.Finalized;

        // Emit the auction ended event
        emit AuctionEnded(currentWinner, highestBid);
    }

    /**
     * @notice Allows the `owner` to distribute the remaining funds of all bidders
     * after the auction has been finalized. This includes refunds for non-winners
     * and the excess deposit of the winner (once the owner has withdrawn the winning bid).
     * @dev Iterates through `allBidderAddresses` and processes funds for any bidder
     * with a remaining `totalDeposited` balance. Applies a 2% commission on each amount returned.
     * Can only be called by the `owner` and only if the auction is in `Finalized` state.
     * This function can be gas-intensive if there are many bidders.
     * THIS ONE is not the best option but the project's requirement explicitly states
     * that the owner is responsible for returning the funds
     * rather than bidders claiming them individually.
     */
    function ownerDistributeAllRemainingFunds()
        public
        onlyOwner
        updateAuctionState
    {
        require(
            currentAuctionState == AuctionState.Finalized,
            "The auction must be finalized for the owner to distribute funds."
        );
        uint256 commissionsFundsDistributed = 0;
        for (uint256 i = 0; i < allBidderAddresses.length; i++) {
            address payable currentBidderAddress = payable(
                allBidderAddresses[i]
            );
            Bidder storage bidder = bidders[currentBidderAddress];

            // Only process if the bidder still has funds (i.e., not yet refunded/processed)
            // and it's not the winner who has already had their winning bid withdrawn.
            if (bidder.totalDeposited > 0) {
                uint256 amountToProcess = bidder.totalDeposited;
                uint256 commissionAmount = (amountToProcess *
                    COMMISSION_PERCENTAGE) / 100;
                uint256 amountToSend = amountToProcess - commissionAmount;

                totalCommissionsCollected += commissionAmount;
                commissionsFundsDistributed += commissionAmount;
                bidder.totalDeposited = 0; // Reset balance to prevent double distribution
                bidder.lastBidAmount = 0; // Also reset lastBidAmount for cleanliness

                (bool success, ) = currentBidderAddress.call{
                    value: amountToSend
                }("");
                require(
                    success,
                    "Failed to send funds to bidder during mass distribution."
                );

                // Emit refund/distribution event
                emit RefundIssued(
                    currentBidderAddress,
                    amountToSend,
                    commissionAmount
                );
            }
        }
        emit FundsDistributed(
            msg.sender,
            commissionsFundsDistributed,
            block.timestamp
        );
    }

    /**
     * @notice Allows the `owner` to withdraw all accumulated commissions from losing bids and distributed excess funds.
     * @dev Can only be executed by the `owner`. Can only be withdrawn if `totalCommissionsCollected` is greater than 0.
     * The `totalCommissionsCollected` commission counter is reset to zero after withdrawal.
     */
    function withdrawAllCommissions() public onlyOwner {
        require(totalCommissionsCollected > 0, "No commissions to withdraw.");

        uint256 amount = totalCommissionsCollected;
        totalCommissionsCollected = 0; // Reset the commission counter

        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Failed to withdraw commissions.");

        // Event emitted
        emit CommissionWithdrawn(owner, amount);
    }

    /**
     * @notice Allows the `owner` to withdraw the winning bid funds.
     * @dev Can only be called by the `owner` once the auction has been `Finalized`.
     * It checks that a winner exists and that the funds have not been withdrawn before.
     * The winner's `totalDeposited` is reduced by the withdrawn amount, leaving any excess
     * to be distributed later by `ownerDistributeAllRemainingFunds`.
     */
    function winnerFundsWithrawn() public onlyOwner {
        require(
            !flagWinnerFundsWithdrawn,
            "Funds have already been withdrawn."
        );
        require(
            currentWinner != address(0),
            "There is no winner to withdraw funds from."
        );
        require(
            currentAuctionState == AuctionState.Finalized,
            "The auction has not ended."
        );

        uint256 amountToTransfer = highestBid;
        require(
            amountToTransfer > 0,
            "No valid amount to withdraw from the winning bid."
        );
        // Reduce the winner's balance by the winning bid amount.
        // Any remaining amount in totalDeposited will be the excess.
        bidders[currentWinner].totalDeposited -= amountToTransfer;
        (bool success, ) = payable(owner).call{value: amountToTransfer}("");
        require(success, "Failed to withdraw the winning amount.");
        flagWinnerFundsWithdrawn = true;

        // Event emitted
        emit OwnerHighestBidWithdrawn(owner, amountToTransfer);
    }

    /**
     * @notice FOR DIDACTIC PURPOSES ONLY. Allows the owner to force the auction into the Finalized state.
     * Can only be called by the owner.
     */
    function forceFinalizeAuctionForDidacticPurposes() public onlyOwner {
        // Require that the auction is not already finalized
        require(
            currentAuctionState != AuctionState.Finalized,
            "Auction is already finalized."
        );
        // Optionally, you might want to prevent finalizing if it's still Pending (hasn't started)
        require(
            currentAuctionState != AuctionState.Pending,
            "Auction has not started yet (Pending); cannot force finalize."
        );

        // Directly set the auction state to Finalized
        currentAuctionState = AuctionState.Finalized;

        // Emit the AuctionEnded event, simulating a natural end
        // This will use the currentWinner and highestBid at the moment of forcing finalization.
        emit AuctionEndedbyForce(currentWinner, highestBid);
    }

    /**
     * @notice Allows the contract owner to withdraw the entire balance of Ether held by the contract.
     * @dev Can only be called by the contract owner.
     * This function is a safety measure to recover any funds that might be held by the contract
     * beyond specific amounts (winning bid, commissions) and ensures the owner can empty the contract.
     */
    function ownerWithdrawContractBalance() external onlyOwner {
        // Get the current balance of the contract.
        uint256 contractBalance = address(this).balance;

        // Require that there is a balance to withdraw.
        require(
            contractBalance > 0,
            "No Ether to withdraw from contract balance."
        );

        // Perform the transfer to the owner.
        (bool success, ) = payable(owner).call{value: contractBalance}("");
        require(success, "Failed to withdraw contract balance.");

        // Emit the event to record the withdrawal.
        emit ContractBalanceWithdrawn(owner, contractBalance);
    }
}
