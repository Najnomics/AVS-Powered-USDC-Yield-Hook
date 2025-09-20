// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DeployYieldOptimizationHook} from "./DeployYieldOptimizationHook.s.sol";

contract DeployMainnet is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY_MAINNET", uint256(0));
        address treasury = vm.envOr("TREASURY_ADDRESS", address(0x1234567890123456789012345678901234567890));
        
        // Validate private key
        require(deployerPrivateKey != 0, "PRIVATE_KEY_MAINNET not set");
        
        // Additional mainnet validations
        require(block.chainid == 1, "Not on mainnet");
        require(treasury != address(0), "Treasury address not set");
        
        // Start broadcasting
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying to mainnet...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Treasury:", treasury);
        console.log("Chain ID:", block.chainid);
        
        // Deploy the hook
        DeployYieldOptimizationHook deployer = new DeployYieldOptimizationHook();
        deployer.run();
        
        vm.stopBroadcast();
        
        console.log("Mainnet deployment completed successfully!");
        console.log("IMPORTANT: Verify contracts on Etherscan");
        console.log("IMPORTANT: Transfer ownership to multisig");
        console.log("IMPORTANT: Set up monitoring and alerts");
    }
}
