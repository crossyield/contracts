//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
@title Treasury
@notice This contract is used to store the funds of the protocol
*/
contract Treasury is Ownable {
    //========================================================================
    //ERRORS
    //========================================================================
    error InsufficientBalance(uint requested, uint available);
    error InvalidAddress();
    error TransferFailed();

    //========================================================================
    //EVENTS
    //========================================================================
    /// @dev Event for Ethers received.
    event Received(address indexed sender, uint amount);

    /// @dev Event for Ethers withdrawn.
    event Withdrawn(address indexed beneficiary, uint amount);

    //========================================================================
    //CONSTRUCTOR
    //========================================================================
    /// @notice Constructor to set the initial owner and optionally receive Ether.
    constructor() payable Ownable(msg.sender) {}

    //========================================================================
    //RECEIVE ETHER
    //========================================================================
    /// @notice Receive Ether.
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
