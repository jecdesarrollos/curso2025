# curso2025
Curso ETH KIPU PM 2025 Jorge Enrique Cabrera 

Index:
#Trabajo Final Modulo 2
#Trabajo Final Modulo 1

# Trabajo Final Modulo 2
Cierre: domingo, 8 de junio de 2025, 23:59
Debes crear un smart contract en Sepolia desde tu address en Ethereum:
El smart contract debe estar publicado y verificado.
La address del smart contract debe quedar registrada aquí:

Smart Contract Address 

Original: 0x22C818F0b72C0730794e524795cB8d3D62f8489c
Reviewed Practical Work Module 2: 0x80d56c66973f7bC34fa19f404D990BAa861A0243

Both Published and verified on Sepolia Testnet

*************************
Reviewd Practical Work Module 2

About the changes in the reviewed Practical Work Module 2:
I have gone through each of the suggestions and made some adjustments. 

Here is a quick summary of the changes:

Partial Withdrawals
Initially, bidders could only withdraw all of their excess deposit. 
I have updated the 'withdrawPartialExcessDeposit' function so users can now take out precisely the amount they need. 
But, as a dedicated function for total refunds was mandatory, I've ensured 'withdrawExcessDeposit' is also present to handle full excess withdrawals.

Short/Long Strings
I have thoroughly reviewed every require and emit message, making them super concise. 

Requires at the Top
I have refactored the placeBid function and others (or checked them) to ensure all validation checks are at the top. 

State variables - Read & Writes in loops
I have adjusted the 'ownerDistributeAllRemainingFunds' function (where most of the looping happens)
It read only one time the array length (e.g., numBidders) before the loop starts.
About "dirty variables": I declared local variables (like currentBidderAddress or amountToProcess) outside the loop and simply reused them inside, instead of re-declaring them in each iteration. 
In some state variable like totalCommissionsCollected, I accumulate the total in a local variable throughout the loop and only write the final sum back to the state variable once after the loop completes.

5. Emergency ETH Recovery Function
Is the function 'ownerWithdrawContractBalance' and I renamed it to 'emergencyWithdrawEther' and added a specific EmergencyFundsWithdrawn event. Now, it's more explicit that this function serves as a last resort to recover any potentially stuck funds.

6. Comprehensive Documentation & English Consistency
Finally, I have thoroughly reviewed and polished the contract's documentation and ensured full English consistency:
Refining the NatSpec comments (@dev, @notice) for functions like withdrawPartialExcessDeposit, withdrawExcessDeposit, and ownerDistributeAllRemainingFunds to be more precise and clear about their purpose, parameters, and returns.
All remaining Spanish comments have been translated into English.

End of the reviewed new version of Auction.sol 

*************************
Original Practical Work Module 2
Considerations for the practical assignment:
block.timestamp usage: For the purpose of this practical assignment, block.timestamp was used. However, it's generally advised against in production environments as it can be subject to miner manipulation.

Owner initiated fund returns: To meet assignment requirements, functions were implemented for the owner to return funds. In a production setting, it would be more advisable for each bidder to claim their own funds. This approach offers better security against certain attacks and significantly reduces blockchain storage costs, as maintaining a history of all distributed funds can become extremely expensive.

Handling excess deposits: The same reasoning applies to the owner's handling of excess deposits from each bidder. It would typically be more efficient for bidders to claim their own excess amounts. 

While I've applied the requested criteria, I've also tried to include more events to obtain better off-chain information later.

Core Functions:

Constructor:

constructor(): Initializes the contract owner, sets the initial minimum bid, and prepares the auction.

startAuction(): Activates the auction, setting its official start and end times.

getCurrentAuctionState(): Returns the current operational state of the auction (Pending, Active, Ended, Finalized).

Auction:

getNextMinimumBidAmount(): Calculates and returns the minimum required bid amount for the next valid offer.

placeBid(uint256 _amount): Allows participants to submit a bid, validating it and updating the auction's highest bid.

Ending and refunds:

getWinner(): Returns the address of the highest bidder and their winning amount once the auction has ended.

withdrawExcessDeposit(): Enables bidders to withdraw any Ether they deposited beyond their last valid bid while the auction is active.

finalizeAuction(): Transitions the auction to the Finalized state, enabling fund distribution by the owner.

ownerDistributeAllRemainingFunds(): Distributes remaining funds to all bidders (refunds to non-winners, excess to winner) after finalization, applying commissions.

winnerFundsWithrawn(): Allows the contract owner to withdraw the winning bid amount from the contract.

withdrawAllCommissions(): Enables the contract owner to withdraw all accumulated commissions from the auction.

ownerWithdrawContractBalance(): Provides a safeguard for the owner to withdraw any residual Ether left in the contract's balance.

getAllBids(): Returns the complete history of all bids made in the auction for didactic purposes.

forceFinalizeAuctionForDidacticPurposes(): Allows the owner to prematurely force the auction into the Finalized state.


* * *

# Trabajo Final Modulo 1
Cierre: martes, 20 de mayo de 2025, 23:59
Debes crear un smart contract en Sepolia desde tu address en Ethereum:
El smart contract debe estar publicado y verificado.
La address del smart contract debe quedar registrada aquí:

Address del smart contract:
0xf1Bd209F5BB04c57c192cbAe1aF0a9c227B54eEa v0.1 3-6-2025

publicado y verificado en Sepolia Testnet

