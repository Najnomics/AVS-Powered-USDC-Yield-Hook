// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DeployYieldOptimizationHook} from "./DeployYieldOptimizationHook.s.sol";

contract DeployTestnet is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY_TESTNET", uint256(0));
        address treasury = vm.envOr("TREASURY_ADDRESS", address(0x1234567890123456789012345678901234567890));
        
        // Validate private key
        require(deployerPrivateKey != 0, "PRIVATE_KEY_TESTNET not set");
        
        // Start broadcasting
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying to testnet...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Treasury:", treasury);
        console.log("Chain ID:", block.chainid);
        
        // Deploy the hook
        DeployYieldOptimizationHook deployer = new DeployYieldOptimizationHook();
        deployer.run();
        
        vm.stopBroadcast();
        
        console.log("Testnet deployment completed successfully!");
    }
}
