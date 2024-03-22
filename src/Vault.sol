//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

//=============================================================================
//IMPORTS
//=============================================================================
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../lib/solmate/src/tokens/ERC4626.sol";
// import "./interfaces/ISyntheticToken.sol";

/**
@title Vault
@notice This contract is used to store the yield strategies of the protocol
*/
contract Vault is ERC4626, ReentrancyGuard {
    //=============================================================================
    //STATE VARIABLES
    //=============================================================================
    struct VaultUser {
        uint points;
        uint debt;
        uint credit;
        uint collateral;
        uint lastRedistributed;
    }
    mapping(address => VaultUser) public vaultUsers;
    address[] public users;
}
