// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DeployYieldOptimizationHook} from "./DeployYieldOptimizationHook.s.sol";

contract DeployAnvil is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY_ANVIL", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address treasury = vm.envOr("TREASURY_ADDRESS", address(0x1234567890123456789012345678901234567890));
        
        // Start broadcasting
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying to Anvil local network...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Treasury:", treasury);
        
        // Deploy the hook
        DeployYieldOptimizationHook deployer = new DeployYieldOptimizationHook();
        deployer.run();
        
        vm.stopBroadcast();
        
        console.log("Deployment completed successfully!");
    }
}
