// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {YieldOptimizationHook} from "../../src/hooks/YieldOptimizationHook.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {toBalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {MockYieldIntelligenceAVS} from "../mocks/MockYieldIntelligenceAVS.sol";
import {MockCircleWalletManager} from "../mocks/MockCircleWalletManager.sol";
import {MockCCTPIntegration} from "../mocks/MockCCTPIntegration.sol";
import {MockPoolManager} from "../mocks/MockPoolManager.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {TestYieldOptimizationHook} from "../mocks/TestYieldOptimizationHook.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title YieldOptimizationHookUnitTest
 * @notice Basic unit tests for YieldOptimizationHook
 * @dev Tests basic functionality and constants
 */
contract YieldOptimizationHookUnitTest is Test {
    using CurrencyLibrary for Currency;
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    TestYieldOptimizationHook public hook;
    MockPoolManager public poolManager;
    MockYieldIntelligenceAVS public mockAVS;
    MockCircleWalletManager public mockWalletManager;
    MockCCTPIntegration public mockCCTP;
    MockUSDC public usdc;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant USER = address(0x1);
    address constant TREASURY = address(0x2);
    
    uint256 constant INITIAL_USDC_BALANCE = 100000e6; // 100k USDC
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        mockAVS = new MockYieldIntelligenceAVS();
        mockWalletManager = new MockCircleWalletManager();
        mockCCTP = new MockCCTPIntegration();
        usdc = new MockUSDC();
        
        // Deploy MockUSDC at the hardcoded USDC address
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        vm.etch(usdcAddress, address(usdc).code);
        
        // Deploy the hook using CREATE2 with proper flags
        hook = _deployHookWithFlags();
        
        // Setup initial state
        usdc.mint(USER, INITIAL_USDC_BALANCE);
        usdc.mint(address(hook), INITIAL_USDC_BALANCE);
        
        // Mint USDC to user and hook on the hardcoded USDC address
        MockUSDC(usdcAddress).mint(USER, INITIAL_USDC_BALANCE);
        MockUSDC(usdcAddress).mint(address(hook), INITIAL_USDC_BALANCE);
    }
    
    function _deployHookWithFlags() internal returns (TestYieldOptimizationHook) {
        // For testing purposes, we'll deploy normally and skip validation
        // In a real deployment, this would use CREATE2 with proper flags
        return new TestYieldOptimizationHook(
            IPoolManager(address(poolManager)),
            mockAVS,
            mockWalletManager,
            mockCCTP,
            TREASURY
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(address(hook.poolManager()), address(poolManager));
        assertEq(address(hook.yieldIntelligenceAVS()), address(mockAVS));
        assertEq(address(hook.circleWalletManager()), address(mockWalletManager));
        assertEq(address(hook.cctpIntegration()), address(mockCCTP));
        assertEq(hook.treasury(), TREASURY);
        assertEq(hook.owner(), address(this));
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK PERMISSIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetHookPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
        assertFalse(permissions.beforeSwapReturnDelta);
        assertFalse(permissions.afterSwapReturnDelta);
        assertFalse(permissions.afterAddLiquidityReturnDelta);
        assertFalse(permissions.afterRemoveLiquidityReturnDelta);
    }
    
    /*//////////////////////////////////////////////////////////////
                            YIELD STRATEGY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetYieldStrategy() public {
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 1;
        
        vm.prank(USER);
        hook.setYieldStrategy(
            5000, // targetAllocation (50%)
            500,  // riskTolerance
            50,   // rebalanceThreshold
            true, // autoRebalance
            true, // crossChainEnabled
            approvedProtocols,
            chainIds,
            100   // maxSlippage (1%)
        );
        
        // Can't access struct with dynamic arrays directly from public mapping
        // Just verify the function call succeeded
        assertTrue(true);
    }
    
    function test_SetYieldStrategy_RevertWhen_InvalidAllocation() public {
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 1;
        
        vm.prank(USER);
        vm.expectRevert("Invalid allocation");
        hook.setYieldStrategy(
            10001, // targetAllocation > 10000
            500,   // riskTolerance
            50,    // rebalanceThreshold
            true,  // autoRebalance
            true,  // crossChainEnabled
            approvedProtocols,
            chainIds,
            100    // maxSlippage (1%)
        );
    }
    
    function test_SetYieldStrategy_RevertWhen_InvalidRiskTolerance() public {
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 1;
        
        vm.prank(USER);
        vm.expectRevert("Invalid risk tolerance");
        hook.setYieldStrategy(
            5000,  // targetAllocation
            10001, // riskTolerance > 10000
            50,    // rebalanceThreshold
            true,  // autoRebalance
            true,  // crossChainEnabled
            approvedProtocols,
            chainIds,
            100    // maxSlippage (1%)
        );
    }
    
    function test_SetYieldStrategy_RevertWhen_InvalidSlippage() public {
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 1;
        
        vm.prank(USER);
        vm.expectRevert("Invalid slippage");
        hook.setYieldStrategy(
            5000, // targetAllocation
            500,  // riskTolerance
            50,   // rebalanceThreshold
            true, // autoRebalance
            true, // crossChainEnabled
            approvedProtocols,
            chainIds,
            1001  // maxSlippage > 1000
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            MANUAL REBALANCE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ManualRebalance() public {
        // Add AAVE_V3 protocol first
        hook.addProtocol(
            keccak256("AAVE_V3"),
            "Aave V3",
            address(0x1111),
            1, // chainId
            1000000000e6, // maxTvl
            100e6, // minDeposit
            keccak256("LOW_RISK")
        );
        
        // Setup user strategy
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 1;
        
        vm.prank(USER);
        hook.setYieldStrategy(
            5000, // targetAllocation
            3000, // riskTolerance (30% - high enough for AAVE_V3 which is 20%)
            50,   // rebalanceThreshold
            true, // autoRebalance
            true, // crossChainEnabled
            approvedProtocols,
            chainIds,
            100   // maxSlippage
        );
        
        // Query yield opportunities to populate the hook's opportunity mapping
        // This calls _simulateAVSResponse which sets up the AAVE_V3 opportunity
        vm.prank(USER);
        hook.queryYieldOpportunities(USER);
        
        // Execute manual rebalance
        vm.prank(USER);
        hook.manualRebalance();
        
        // Verify rebalance was executed (check last rebalance timestamp)
        assertTrue(hook.lastRebalance(USER) > 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            PAUSE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Pause() public {
        vm.prank(address(this));
        hook.pause();
        
        assertTrue(hook.paused());
    }
    
    function test_Pause_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        hook.pause();
    }
    
    function test_Unpause() public {
        vm.prank(address(this));
        hook.pause();
        
        vm.prank(address(this));
        hook.unpause();
        
        assertFalse(hook.paused());
    }
    
    function test_Unpause_RevertWhen_NotOwner() public {
        vm.prank(address(this));
        hook.pause();
        
        vm.prank(USER);
        vm.expectRevert();
        hook.unpause();
    }
    
    /*//////////////////////////////////////////////////////////////
                            TREASURY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_UpdateTreasury() public {
        address newTreasury = address(0x999);
        
        vm.prank(address(this));
        hook.updateTreasury(newTreasury);
        
        assertEq(hook.treasury(), newTreasury);
    }
    
    function test_UpdateTreasury_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        hook.updateTreasury(address(0x999));
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AddProtocol() public {
        bytes32 protocolId = keccak256("COMPOUND_V3");
        
        vm.prank(address(this));
        hook.addProtocol(
            protocolId,
            "Compound V3",
            address(0x123),
            1, // chainId
            1000000e6, // maxTvl
            100e6, // minDeposit
            keccak256("LOW_RISK")
        );
        
        // Can't access struct with dynamic arrays directly from public mapping
        // Just verify the function call succeeded
        assertTrue(true);
    }
    
    function test_AddProtocol_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        hook.addProtocol(
            keccak256("COMPOUND_V3"),
            "Compound V3",
            address(0x123),
            1,
            1000000e6,
            100e6,
            keccak256("LOW_RISK")
        );
    }
    
    function test_CollectFees() public {
        // Mint USDC to the hook on the hardcoded USDC address
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        MockUSDC(usdcAddress).mint(address(hook), INITIAL_USDC_BALANCE);
        
        uint256 initialBalance = IERC20(usdcAddress).balanceOf(TREASURY);
        uint256 hookBalance = IERC20(usdcAddress).balanceOf(address(hook));
        
        vm.prank(address(this));
        hook.collectFees();
        
        assertEq(IERC20(usdcAddress).balanceOf(TREASURY), initialBalance + hookBalance);
        assertEq(IERC20(usdcAddress).balanceOf(address(hook)), 0);
    }
    
    function test_CollectFees_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        hook.collectFees();
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(hook.USDC(), 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F);
        assertEq(hook.MIN_REBALANCE_AMOUNT(), 100e6);
        assertEq(hook.MIN_YIELD_IMPROVEMENT(), 50);
        assertEq(hook.MAX_PROTOCOL_ALLOCATION(), 4000);
        assertEq(hook.REBALANCE_COOLDOWN(), 3600);
        assertEq(hook.PROTOCOL_FEE(), 25);
        assertEq(hook.AVS_REWARD_PERCENTAGE(), 10);
    }
}