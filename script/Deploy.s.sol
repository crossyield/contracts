// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {CyDyson} from "../src/cyDYSON.sol";
import {Treasury} from "../src/Treasury.sol";
import {ICYDyson} from "../src/interface/ICYDyson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "../src/Vault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Deploy is Script {
    function run() external {
        //CONSTANTS
        bytes32 CROSS_YIELD_SALT = bytes32(
            abi.encode(0x43726f73735969656c645f7632)
        ); // ~ "CrossYield_V2"

        /// @dev Address to store the DYSON token on Sepolia
        address DYSON = 0xaBAD60e4e01547E2975a96426399a5a0578223Cb;

        /// @dev Address to store the USDC token on Sepolia
        address USDC = (address(0xf97B79eCE2F95e7B63a05F1FD73a59A1eF3E4fd7));

        address UNDERLYING_STRATEGY_ASSET = 0xf97B79eCE2F95e7B63a05F1FD73a59A1eF3E4fd7;
        uint256 MAX_VAULT_CAPACITY = 5000000 * 10 ** 6; //5000000000000000000000000
        string memory POINTS_NAME = "cyUSDC";
        string memory POINTS_SYMBOL = "CY_USDC";

        uint256 privKey = vm.envUint("PRIV_KEY");

        // set up deployer
        address deployer = vm.rememberKey(privKey);

        // log deployer data
        console2.log("Deployer: ", deployer);
        console2.log("Deployer Nonce: ", vm.getNonce(deployer));

        vm.startBroadcast(deployer);

        // 1. Deploy Treasury contract w/ an optional Salt
        Treasury treasury = new Treasury();

        // 2. Deploy SyntheticToken contract
        CyDyson cyDyson = new CyDyson();

        // 3. Create a new USDC Vault
        Vault newVault = new Vault(
            msg.sender,
            UNDERLYING_STRATEGY_ASSET,
            MAX_VAULT_CAPACITY,
            POINTS_NAME,
            POINTS_SYMBOL,
            ICYDyson(address(cyDyson)),
            address(treasury)
        );

        //5. Transfer ownership of the SyntheticToken to the new Vault
        // cyDyson.addVault(address(newVault));

        // // 6. Approve USDC for trade on the Vault
        // IERC20(UNDERLYING_STRATEGY_ASSET).approve(
        //     address(newVault),
        //     MAX_VAULT_CAPACITY
        // );

        // // 7. Approve the Vault Points for trade on the Vault
        // Vault(newVault).approve(address(newVault), MAX_VAULT_CAPACITY);

        // 8. Deposit
        // Vault(newVault).depositToVault(USDC, DYSON, 500 * 10 ** 6);

        // 9. Borrow
        // Vault(newVault).borrow(250 * 10 ** 6);

        // 10. Simulate yield being given
        // Vault(newVault).redistributeYield(0);

        vm.stopBroadcast();

        // log deployment data
        console2.log("Treasury: ", address(treasury));
        console2.log("CyDyson: ", address(cyDyson));
        console2.log("Vault: ", address(newVault));
    }
}
