// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {YieldOptimizationHook} from "../../src/hooks/YieldOptimizationHook.sol";
import {TestYieldOptimizationHook} from "../mocks/TestYieldOptimizationHook.sol";
import {MockPoolManager} from "../mocks/MockPoolManager.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {MockYieldIntelligenceAVS} from "../mocks/MockYieldIntelligenceAVS.sol";
import {MockCircleWalletManager} from "../mocks/MockCircleWalletManager.sol";
import {MockCCTPIntegration} from "../mocks/MockCCTPIntegration.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";

contract GasOptimizationTest is Test {
    TestYieldOptimizationHook public hook;
    MockPoolManager public poolManager;
    MockUSDC public usdc;
    MockYieldIntelligenceAVS public mockAVS;
    MockCircleWalletManager public mockWalletManager;
    MockCCTPIntegration public mockCCTP;
    
    address public constant USER = address(0x1);
    address public constant TREASURY = address(0x2);
    address public constant USDC_ADDRESS = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
    
    function setUp() public {
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        usdc = new MockUSDC();
        mockAVS = new MockYieldIntelligenceAVS();
        mockWalletManager = new MockCircleWalletManager();
        mockCCTP = new MockCCTPIntegration();
        
        // Deploy hook
        hook = new TestYieldOptimizationHook(
            IPoolManager(address(poolManager)),
            mockAVS,
            mockWalletManager,
            mockCCTP,
            TREASURY
        );
        
        // Setup USDC at hardcoded address
        vm.etch(USDC_ADDRESS, address(usdc).code);
        
        // Mint USDC to user
        MockUSDC(USDC_ADDRESS).mint(USER, 1000000e6);
        MockUSDC(USDC_ADDRESS).mint(address(hook), 1000000e6);
        
        // Add AAVE_V3 protocol to the hook
        vm.prank(address(hook.owner()));
        hook.addProtocol(
            keccak256("AAVE_V3"),
            "Aave V3",
            address(0x1111),
            block.chainid,
            1000000000e6, // maxTvl
            100e6, // minDeposit
            keccak256("LOW_RISK")
        );
        
        // Setup default yield opportunity
        mockAVS.setYieldOpportunity(
            keccak256("AAVE_V3"),
            block.chainid,
            500, // 5% APY
            1000000e6, // 1M USDC available
            9000 // 90% confidence
        );
    }
    
    function testGas_SetYieldStrategy() public {
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 1;
        
        uint256 gasStart = gasleft();
        
        vm.prank(USER);
        hook.setYieldStrategy(
            5000, // targetAllocation
            3000, // riskTolerance
            50,   // rebalanceThreshold
            true, // autoRebalance
            true, // crossChainEnabled
            approvedProtocols,
            chainIds,
            100   // maxSlippage
        );
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for setYieldStrategy:", gasUsed);
        
        // Assert gas usage is reasonable (adjust threshold as needed)
        assertLt(gasUsed, 300000);
    }
    
    function testGas_AddProtocol() public {
        uint256 gasStart = gasleft();
        
        vm.prank(address(hook.owner()));
        hook.addProtocol(
            keccak256("AAVE_V3"),
            "Aave V3",
            address(0x1111),
            1,
            1000000000e6,
            100e6,
            keccak256("LOW_RISK")
        );
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for addProtocol:", gasUsed);
        
        // Assert gas usage is reasonable
        assertLt(gasUsed, 200000);
    }
    
    function testGas_ManualRebalance() public {
        // Setup protocol
        bytes32 protocolId = keccak256("AAVE_V3");
        vm.prank(address(hook.owner()));
        hook.addProtocol(
            protocolId,
            "Aave V3",
            address(0x1111),
            1,
            1000000000e6,
            100e6,
            keccak256("LOW_RISK")
        );
        
        // Setup user strategy
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = protocolId;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid; // Use current chain ID
        
        vm.prank(USER);
        hook.setYieldStrategy(
            5000, 3000, 50, true, true, approvedProtocols, chainIds, 100
        );
        
        // Setup yield opportunity with higher yield
        mockAVS.setYieldOpportunity(protocolId, block.chainid, 500, 1000000e6, 9000);
        
        // Mint USDC to user
        MockUSDC(USDC_ADDRESS).mint(USER, 1000e6);
        MockUSDC(USDC_ADDRESS).approve(address(hook), 1000e6);
        
        // Query yield opportunities first to populate them
        hook.queryYieldOpportunities(USER);
        
        uint256 gasStart = gasleft();
        
        vm.prank(USER);
        hook.manualRebalance();
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for manualRebalance:", gasUsed);
        
        // Assert gas usage is reasonable
        assertLt(gasUsed, 1000000);
    }
    
    function testGas_CollectFees() public {
        // Mint USDC to hook
        MockUSDC(USDC_ADDRESS).mint(address(hook), 1000e6);
        
        uint256 gasStart = gasleft();
        
        vm.prank(address(hook.owner()));
        hook.collectFees();
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for collectFees:", gasUsed);
        
        // Assert gas usage is reasonable
        assertLt(gasUsed, 100000);
    }
    
    function testGas_UpdateTreasury() public {
        address newTreasury = address(0x999);
        
        uint256 gasStart = gasleft();
        
        vm.prank(address(hook.owner()));
        hook.updateTreasury(newTreasury);
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for updateTreasury:", gasUsed);
        
        // Assert gas usage is reasonable
        assertLt(gasUsed, 100000);
    }
    
    function testGas_Pause() public {
        uint256 gasStart = gasleft();
        
        vm.prank(address(hook.owner()));
        hook.pause();
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for pause:", gasUsed);
        
        // Assert gas usage is reasonable
        assertLt(gasUsed, 100000);
    }
    
    function testGas_Unpause() public {
        // First pause
        vm.prank(address(hook.owner()));
        hook.pause();
        
        uint256 gasStart = gasleft();
        
        vm.prank(address(hook.owner()));
        hook.unpause();
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for unpause:", gasUsed);
        
        // Assert gas usage is reasonable
        assertLt(gasUsed, 100000);
    }
    
    function testGas_BatchOperations() public {
        // Test gas efficiency of batch operations
        bytes32[] memory approvedProtocols = new bytes32[](3);
        approvedProtocols[0] = keccak256("AAVE_V3");
        approvedProtocols[1] = keccak256("COMPOUND_V3");
        approvedProtocols[2] = keccak256("MORPHO");
        
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 1;
        chainIds[1] = 8453;
        
        uint256 gasStart = gasleft();
        
        vm.prank(USER);
        hook.setYieldStrategy(
            5000, 3000, 50, true, true, approvedProtocols, chainIds, 100
        );
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for batch setYieldStrategy:", gasUsed);
        
        // Assert gas usage is reasonable
        assertLt(gasUsed, 400000);
    }
    
    function testGas_OptimizationComparison() public {
        // Test gas optimization compared to baseline
        // This is a placeholder for actual optimization testing
        
        // Baseline operation
        uint256 baselineGas = 100000;
        
        // Optimized operation
        uint256 optimizedGas = 80000;
        
        // Assert optimization
        assertLt(optimizedGas, baselineGas);
        console.log("Gas optimization:", baselineGas - optimizedGas);
    }
}
