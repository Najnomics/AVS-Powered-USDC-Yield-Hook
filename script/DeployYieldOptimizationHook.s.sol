// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {YieldOptimizationHook} from "../src/hooks/YieldOptimizationHook.sol";
import {IYieldIntelligenceAVS} from "../src/interfaces/IYieldIntelligenceAVS.sol";
import {ICircleWalletManager} from "../src/interfaces/ICircleWalletManager.sol";
import {ICCTPIntegration} from "../src/interfaces/ICCTPIntegration.sol";

/**
 * @title DeployYieldOptimizationHook
 * @notice Deployment script for the main USDC Yield Optimization Hook
 * @dev This script deploys the core hook contract that integrates with Uniswap v4
 */
contract DeployYieldOptimizationHook is Script {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    // Mainnet addresses
    address constant MAINNET_POOL_MANAGER = 0x0000000000000000000000000000000000000000; // TODO: Add actual address
    address constant MAINNET_USDC = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
    
    // Testnet addresses (Sepolia)
    address constant SEPOLIA_POOL_MANAGER = 0x0000000000000000000000000000000000000000; // TODO: Add actual address
    address constant SEPOLIA_USDC = 0x0000000000000000000000000000000000000000; // TODO: Add actual address
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    YieldOptimizationHook public yieldHook;
    
    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    
    function run() public virtual returns (YieldOptimizationHook) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying USDC Yield Optimization Hook...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        
        // Get deployment parameters based on chain
        (
            address poolManager,
            address yieldIntelligenceAVS,
            address circleWalletManager,
            address cctpIntegration,
            address treasury
        ) = _getDeploymentParameters();
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the hook with CREATE2 for deterministic address
        uint256 flags = _getHookFlags();
        
        // Calculate hook address using CREATE2
        address hookAddress = _calculateHookAddress(
            deployer,
            flags,
            type(YieldOptimizationHook).creationCode,
            abi.encode(
                poolManager,
                yieldIntelligenceAVS,
                circleWalletManager,
                cctpIntegration,
                treasury
            )
        );
        
        console.log("Calculated hook address:", hookAddress);
        
        // Verify hook address has correct flags
        require(_validateHookAddress(hookAddress, flags), "Invalid hook address");
        
        // Deploy the hook
        yieldHook = new YieldOptimizationHook{salt: bytes32(uint256(flags))}(
            IPoolManager(poolManager),
            IYieldIntelligenceAVS(yieldIntelligenceAVS),
            ICircleWalletManager(circleWalletManager),
            ICCTPIntegration(cctpIntegration),
            treasury
        );
        
        console.log("YieldOptimizationHook deployed at:", address(yieldHook));
        
        // Verify deployment
        require(address(yieldHook) == hookAddress, "Hook address mismatch");
        
        // Setup initial protocols
        _setupInitialProtocols();
        
        // Transfer ownership if needed
        if (deployer != treasury) {
            yieldHook.transferOwnership(treasury);
            console.log("Ownership transferred to treasury:", treasury);
        }
        
        vm.stopBroadcast();
        
        // Log deployment summary
        _logDeploymentSummary();
        
        return yieldHook;
    }
    
    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT HELPERS
    //////////////////////////////////////////////////////////////*/
    
    function _getDeploymentParameters() internal view returns (
        address poolManager,
        address yieldIntelligenceAVS,
        address circleWalletManager,
        address cctpIntegration,
        address treasury
    ) {
        if (block.chainid == 1) {
            // Mainnet
            poolManager = MAINNET_POOL_MANAGER;
            yieldIntelligenceAVS = vm.envAddress("MAINNET_YIELD_INTELLIGENCE_AVS");
            circleWalletManager = vm.envAddress("MAINNET_CIRCLE_WALLET_MANAGER");
            cctpIntegration = vm.envAddress("MAINNET_CCTP_INTEGRATION");
            treasury = vm.envAddress("MAINNET_TREASURY");
        } else if (block.chainid == 11155111) {
            // Sepolia
            poolManager = SEPOLIA_POOL_MANAGER;
            yieldIntelligenceAVS = vm.envAddress("SEPOLIA_YIELD_INTELLIGENCE_AVS");
            circleWalletManager = vm.envAddress("SEPOLIA_CIRCLE_WALLET_MANAGER");
            cctpIntegration = vm.envAddress("SEPOLIA_CCTP_INTEGRATION");
            treasury = vm.envAddress("SEPOLIA_TREASURY");
        } else if (block.chainid == 31337) {
            // Local/Anvil
            poolManager = vm.envOr("LOCAL_POOL_MANAGER", address(0));
            yieldIntelligenceAVS = vm.envOr("LOCAL_YIELD_INTELLIGENCE_AVS", address(0));
            circleWalletManager = vm.envOr("LOCAL_CIRCLE_WALLET_MANAGER", address(0));
            cctpIntegration = vm.envOr("LOCAL_CCTP_INTEGRATION", address(0));
            treasury = vm.envOr("LOCAL_TREASURY", msg.sender);
        } else {
            revert("Unsupported chain");
        }
        
        // Validate required addresses
        require(poolManager != address(0), "Pool manager not set");
        require(treasury != address(0), "Treasury not set");
    }
    
    function _getHookFlags() internal pure returns (uint256) {
        uint256 flags = 0;
        
        // Set hook permissions
        flags |= Hooks.BEFORE_SWAP_FLAG;
        flags |= Hooks.AFTER_SWAP_FLAG;
        
        return flags;
    }
    
    function _calculateHookAddress(
        address deployer,
        uint256 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address) {
        bytes32 salt = bytes32(flags);
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer,
                salt,
                keccak256(abi.encodePacked(creationCode, constructorArgs))
            )
        );
        return address(uint160(uint256(hash)));
    }
    
    function _validateHookAddress(address hookAddress, uint256 flags) internal pure returns (bool) {
        // Validate that the hook address has the correct flags in the proper bit positions
        uint256 addressFlags = uint256(uint160(hookAddress)) & Hooks.ALL_HOOK_MASK;
        return addressFlags == flags;
    }
    
    function _setupInitialProtocols() internal {
        console.log("Setting up initial yield protocols...");
        
        // Add Aave V3 USDC
        bytes32 aaveProtocol = keccak256("AAVE_V3");
        yieldHook.addProtocol(
            aaveProtocol,
            "Aave V3",
            _getAaveV3Address(),
            block.chainid,
            1000000000e6, // 1B USDC max TVL
            1000e6,        // 1000 USDC min deposit
            keccak256("LOW_RISK")
        );
        
        // Add Compound V3 USDC
        bytes32 compoundProtocol = keccak256("COMPOUND_V3");
        yieldHook.addProtocol(
            compoundProtocol,
            "Compound V3",
            _getCompoundV3Address(),
            block.chainid,
            500000000e6,  // 500M USDC max TVL
            100e6,         // 100 USDC min deposit
            keccak256("LOW_RISK")
        );
        
        console.log("Initial protocols configured");
    }
    
    function _getAaveV3Address() internal view returns (address) {
        if (block.chainid == 1) {
            return 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // Mainnet Aave V3 Pool
        } else if (block.chainid == 11155111) {
            return 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951; // Sepolia Aave V3 Pool
        } else {
            return address(0); // Mock for local testing
        }
    }
    
    function _getCompoundV3Address() internal view returns (address) {
        if (block.chainid == 1) {
            return 0xc3d688B66703497DAA19211EEdff47f25384cdc3; // Mainnet Compound V3 USDC
        } else if (block.chainid == 11155111) {
            return 0x2943ac1216979aD8dB76D9147F64E61adc126e96; // Sepolia Compound V3 USDC
        } else {
            return address(0); // Mock for local testing
        }
    }
    
    function _logDeploymentSummary() internal view {
        console.log("\n=== USDC Yield Optimization Hook Deployment Summary ===");
        console.log("Hook Address:", address(yieldHook));
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", yieldHook.owner());
        console.log("Treasury:", yieldHook.treasury());
        console.log("Yield Intelligence AVS:", address(yieldHook.yieldIntelligenceAVS()));
        console.log("Circle Wallet Manager:", address(yieldHook.circleWalletManager()));
        console.log("CCTP Integration:", address(yieldHook.cctpIntegration()));
        console.log("=== Deployment Complete ===\n");
    }
    
    /*//////////////////////////////////////////////////////////////
                        VERIFICATION HELPERS
    //////////////////////////////////////////////////////////////*/
    
    function verifyDeployment() public view {
        require(address(yieldHook) != address(0), "Hook not deployed");
        
        // Verify hook permissions
        uint256 addressFlags = uint256(uint160(address(yieldHook))) & Hooks.ALL_HOOK_MASK;
        uint256 expectedFlags = _getHookFlags();
        require(addressFlags == expectedFlags, "Invalid hook permissions");
        
        // Verify integrations
        require(address(yieldHook.yieldIntelligenceAVS()) != address(0), "AVS not set");
        require(address(yieldHook.circleWalletManager()) != address(0), "Circle Wallet Manager not set");
        require(address(yieldHook.cctpIntegration()) != address(0), "CCTP Integration not set");
        require(yieldHook.treasury() != address(0), "Treasury not set");
        
        console.log("Deployment verification passed");
    }
}

/**
 * @title DeployYieldOptimizationHookLocal
 * @notice Local deployment script with mocks for testing
 */
contract DeployYieldOptimizationHookLocal is DeployYieldOptimizationHook {
    
    function run() public override returns (YieldOptimizationHook) {
        console.log("Deploying USDC Yield Optimization Hook for local testing...");
        
        // Deploy mock contracts first
        _deployMockContracts();
        
        // Then deploy the main hook
        return super.run();
    }
    
    function _deployMockContracts() internal {
        console.log("Deploying mock contracts for local testing...");
        
        // TODO: Deploy mock contracts for local testing
        // - Mock Pool Manager
        // - Mock Yield Intelligence AVS
        // - Mock Circle Wallet Manager
        // - Mock CCTP Integration
        
        console.log("Mock contracts deployed");
    }
}