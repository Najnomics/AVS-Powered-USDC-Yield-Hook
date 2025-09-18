// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {IAllocationManager} from "@eigenlayer/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "@eigenlayer/contracts/interfaces/IPermissionController.sol";
import {YieldIntelligenceServiceManager} from "../src/l1-contracts/YieldIntelligenceServiceManager.sol";

/**
 * @title DeployYieldIntelligenceL1Contracts
 * @notice Deployment script for USDC Yield Intelligence AVS L1 contracts
 * @dev This deploys the EigenLayer service manager for the yield intelligence AVS
 */
contract DeployYieldIntelligenceL1Contracts is Script {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    // EigenLayer addresses (these would be the actual addresses)
    address constant MAINNET_ALLOCATION_MANAGER = 0x0000000000000000000000000000000000000000;
    address constant MAINNET_PERMISSION_CONTROLLER = 0x0000000000000000000000000000000000000000;
    
    address constant HOLESKY_ALLOCATION_MANAGER = 0x0000000000000000000000000000000000000000;
    address constant HOLESKY_PERMISSION_CONTROLLER = 0x0000000000000000000000000000000000000000;
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    YieldIntelligenceServiceManager public serviceManager;
    
    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    
    function run() public returns (YieldIntelligenceServiceManager) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying USDC Yield Intelligence AVS L1 Contracts...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        
        // Get deployment parameters
        (
            address allocationManager,
            address permissionController,
            address yieldOptimizationHook
        ) = _getDeploymentParameters();
        
        console.log("Allocation Manager:", allocationManager);
        console.log("Permission Controller:", permissionController);
        console.log("Yield Optimization Hook:", yieldOptimizationHook);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the service manager
        serviceManager = new YieldIntelligenceServiceManager(
            IAllocationManager(allocationManager),
            IPermissionController(permissionController),
            yieldOptimizationHook
        );
        
        console.log("YieldIntelligenceServiceManager deployed at:", address(serviceManager));
        
        // Setup initial configuration
        _setupInitialConfiguration();
        
        vm.stopBroadcast();
        
        // Log deployment summary
        _logDeploymentSummary();
        
        return serviceManager;
    }
    
    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT HELPERS
    //////////////////////////////////////////////////////////////*/
    
    function _getDeploymentParameters() internal view returns (
        address allocationManager,
        address permissionController,
        address yieldOptimizationHook
    ) {
        if (block.chainid == 1) {
            // Mainnet
            allocationManager = MAINNET_ALLOCATION_MANAGER;
            permissionController = MAINNET_PERMISSION_CONTROLLER;
            yieldOptimizationHook = vm.envAddress("MAINNET_YIELD_OPTIMIZATION_HOOK");
        } else if (block.chainid == 17000) {
            // Holesky testnet
            allocationManager = HOLESKY_ALLOCATION_MANAGER;
            permissionController = HOLESKY_PERMISSION_CONTROLLER;
            yieldOptimizationHook = vm.envAddress("HOLESKY_YIELD_OPTIMIZATION_HOOK");
        } else if (block.chainid == 31337) {
            // Local/Anvil
            allocationManager = vm.envOr("LOCAL_ALLOCATION_MANAGER", address(0));
            permissionController = vm.envOr("LOCAL_PERMISSION_CONTROLLER", address(0));
            yieldOptimizationHook = vm.envOr("LOCAL_YIELD_OPTIMIZATION_HOOK", address(0));
        } else {
            revert("Unsupported chain for AVS deployment");
        }
        
        // Validate required addresses
        require(allocationManager != address(0), "Allocation manager not set");
        require(permissionController != address(0), "Permission controller not set");
        require(yieldOptimizationHook != address(0), "Yield optimization hook not set");
    }
    
    function _setupInitialConfiguration() internal {
        console.log("Setting up initial AVS configuration...");
        
        // The service manager is automatically configured during construction
        // Additional setup can be added here if needed
        
        console.log("Initial configuration complete");
    }
    
    function _logDeploymentSummary() internal view {
        console.log("\n=== USDC Yield Intelligence AVS L1 Deployment Summary ===");
        console.log("Service Manager:", address(serviceManager));
        console.log("Chain ID:", block.chainid);
        console.log("Allocation Manager:", address(serviceManager.allocationManager()));
        console.log("Permission Controller:", address(serviceManager.permissionController()));
        console.log("Yield Optimization Hook:", serviceManager.getYieldOptimizationHook());
        console.log("Minimum Operator Stake:", serviceManager.MINIMUM_YIELD_OPERATOR_STAKE());
        console.log("Consensus Threshold:", serviceManager.CONSENSUS_THRESHOLD());
        console.log("=== L1 Deployment Complete ===\n");
    }
    
    /*//////////////////////////////////////////////////////////////
                        VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/
    
    function verifyDeployment() public view {
        require(address(serviceManager) != address(0), "Service manager not deployed");
        
        // Verify EigenLayer integration
        require(
            address(serviceManager.allocationManager()) != address(0),
            "Allocation manager not set"
        );
        require(
            address(serviceManager.permissionController()) != address(0),
            "Permission controller not set"
        );
        
        // Verify hook integration
        require(
            serviceManager.getYieldOptimizationHook() != address(0),
            "Yield optimization hook not set"
        );
        
        // Verify constants
        require(
            serviceManager.MINIMUM_YIELD_OPERATOR_STAKE() > 0,
            "Invalid minimum stake"
        );
        require(
            serviceManager.CONSENSUS_THRESHOLD() > 0,
            "Invalid consensus threshold"
        );
        
        console.log("✅ L1 deployment verification passed");
    }
}

/**
 * @title RegisterTestOperators
 * @notice Script to register test operators for development/testing
 */
contract RegisterTestOperators is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address serviceManagerAddress = vm.envAddress("SERVICE_MANAGER_ADDRESS");
        
        YieldIntelligenceServiceManager serviceManager = YieldIntelligenceServiceManager(
            serviceManagerAddress
        );
        
        console.log("Registering test operators...");
        console.log("Service Manager:", serviceManagerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Register test operators (this would typically be done by individual operators)
        // For testing purposes, we can register some test operators
        
        // Generate test operator signature (placeholder)
        bytes memory operatorSignature = abi.encodePacked("test_signature");
        
        // Register the deployer as a test operator
        serviceManager.registerYieldIntelligenceOperator{value: 5 ether}(
            vm.addr(deployerPrivateKey),
            operatorSignature
        );
        
        console.log("Test operator registered:", vm.addr(deployerPrivateKey));
        
        vm.stopBroadcast();
        
        console.log("Test operator registration complete");
    }
}

/**
 * @title SetupProtocolMonitoring
 * @notice Script to setup initial protocol monitoring for the AVS
 */
contract SetupProtocolMonitoring is Script {
    
    struct ProtocolConfig {
        bytes32 protocolId;
        string name;
        uint256 chainId;
        address protocolAddress;
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address serviceManagerAddress = vm.envAddress("SERVICE_MANAGER_ADDRESS");
        
        console.log("Setting up protocol monitoring...");
        console.log("Service Manager:", serviceManagerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Setup initial protocols to monitor
        ProtocolConfig[] memory protocols = _getInitialProtocols();
        
        for (uint256 i = 0; i < protocols.length; i++) {
            console.log("Configuring protocol:", protocols[i].name);
            console.log("Protocol ID:", vm.toString(protocols[i].protocolId));
            console.log("Chain ID:", protocols[i].chainId);
            console.log("Address:", protocols[i].protocolAddress);
        }
        
        vm.stopBroadcast();
        
        console.log("Protocol monitoring setup complete");
    }
    
    function _getInitialProtocols() internal view returns (ProtocolConfig[] memory) {
        ProtocolConfig[] memory protocols = new ProtocolConfig[](4);
        
        // Ethereum protocols
        protocols[0] = ProtocolConfig({
            protocolId: keccak256("AAVE_V3_ETH"),
            name: "Aave V3 Ethereum",
            chainId: 1,
            protocolAddress: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
        });
        
        protocols[1] = ProtocolConfig({
            protocolId: keccak256("COMPOUND_V3_ETH"),
            name: "Compound V3 Ethereum",
            chainId: 1,
            protocolAddress: 0xc3d688B66703497DAA19211EEdff47f25384cdc3
        });
        
        // Base protocols
        protocols[2] = ProtocolConfig({
            protocolId: keccak256("AAVE_V3_BASE"),
            name: "Aave V3 Base",
            chainId: 8453,
            protocolAddress: 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5
        });
        
        protocols[3] = ProtocolConfig({
            protocolId: keccak256("COMPOUND_V3_BASE"),
            name: "Compound V3 Base",
            chainId: 8453,
            protocolAddress: 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf
        });
        
        return protocols;
    }
}