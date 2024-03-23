// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {cyDYSON} from "../src/cyDYSON.sol";
import {Treasury} from "../src/Treasury.sol";
import {ICYDyson} from "../src/interface/ICYDyson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "../src/Vault.sol";

contract Deploy is Script {
    function run() external {
        //CONSTANTS
        bytes32 CROSS_YIELD_SALT = bytes32(
            abi.encode(0x43726f73735969656c645f7632)
        ); // ~ "CrossYield_V2"

        /// @dev Address to store the DYSON token on Sepolia
        address DYSON = 0xeDC2B3Bebbb4351a391363578c4248D672Ba7F9B;

        /// @dev Address to store the USDC token on Sepolia
        address USDC = 0xFA0bd2B4d6D629AdF683e4DCA310c562bCD98E4E;

        address UNDERLYING_STRATEGY_ASSET = 0xFA0bd2B4d6D629AdF683e4DCA310c562bCD98E4E;
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
        Treasury treasury = new Treasury{salt: CROSS_YIELD_SALT}();

        // 2. Deploy SyntheticToken contract
        ICYDyson icyDyson = new ICYDyson();

        // 3. Create a new USDC Vault
        Vault vault = new Vault(
            msg.sender,
            USDC,
            MAX_VAULT_CAPACITY,
            POINTS_NAME,
            POINTS_SYMBOL,
            address(icyDyson),
            address(treasury)
        );

        //5. Transfer ownership of the SyntheticToken to the new Vault
        icyDyson.addVault(address(newVault));

        //6. Approve USDC for trade on the Vault
        IERC20(UNDERLYING_STRATEGY_ASSET).approve(
            address(newVault),
            MAX_VAULT_CAPACITY
        );

        //7. Approve the Vault Points for trade on the Vault
        IERC20(newVault).approve(address(newVault), MAX_VAULT_CAPACITY);

        //8. Deposit
        Vault(newVault).depositToVault(USDC, DYSON, 500 * 10 ** 6);

        //9. Borrow
        Vault(newVault).borrow(250 * 10 ** 6);

        //10. Simulate yield being given
        Vault(newVault).redistributeYield(0);

        vm.stopBroadcast();

        // log deployment data
        console2.log("Treasury: ", address(treasury));
        console2.log("ICYDyson: ", address(icyDyson));
        console2.log("Vault: ", address(vault));
}
