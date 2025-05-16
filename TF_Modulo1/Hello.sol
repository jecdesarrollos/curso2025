// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Hello {
string internal name = "World";

    function setName(string calldata _name) external {
        name = _name;
    }

    function getName() external view returns (string memory _name) {
        return string(abi.encodePacked("Hello, ", name));
    }
    
}