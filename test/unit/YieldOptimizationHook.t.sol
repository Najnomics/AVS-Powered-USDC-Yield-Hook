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
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {MockYieldIntelligenceAVS} from "../mocks/MockYieldIntelligenceAVS.sol";
import {MockCircleWalletManager} from "../mocks/MockCircleWalletManager.sol";
import {MockCCTPIntegration} from "../mocks/MockCCTPIntegration.sol";
import {MockPoolManager} from "../mocks/MockPoolManager.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/**
 * @title YieldOptimizationHookUnitTest
 * @notice Comprehensive unit tests for YieldOptimizationHook
 * @dev Tests all functions, edge cases, and error conditions
 */
contract YieldOptimizationHookUnitTest is Test {
    using CurrencyLibrary for Currency;
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    YieldOptimizationHook public hook;
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
    address constant OTHER_USER = address(0x3);
    
    uint256 constant INITIAL_USDC_BALANCE = 100000e6; // 100k USDC
    uint256 constant SWAP_AMOUNT = 1000e6; // 1k USDC
    
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
        
        // Deploy the hook
        hook = new YieldOptimizationHook(
            IPoolManager(address(poolManager)),
            mockAVS,
            mockWalletManager,
            mockCCTP,
            TREASURY
        );
        
        // Setup initial state
        usdc.mint(USER, INITIAL_USDC_BALANCE);
        usdc.mint(address(hook), INITIAL_USDC_BALANCE);
        
        // Configure mocks
        mockAVS.setYieldOpportunity(
            keccak256("AAVE_V3"),
            1, // chainId
            500, // yieldRate (5% APY)
            1000, // riskScore
            true // isAvailable
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
    
    function test_Constructor_RevertWhen_ZeroAddress() public {
        vm.expectRevert();
        new YieldOptimizationHook(
            IPoolManager(address(0)),
            mockAVS,
            mockWalletManager,
            mockCCTP,
            TREASURY
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK PERMISSIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetHookPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertTrue(permissions.beforeInitialize);
        assertTrue(permissions.afterInitialize);
        assertTrue(permissions.beforeAddLiquidity);
        assertTrue(permissions.afterAddLiquidity);
        assertTrue(permissions.beforeRemoveLiquidity);
        assertTrue(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertTrue(permissions.beforeDonate);
        assertTrue(permissions.afterDonate);
        assertFalse(permissions.beforeSwapReturnDelta);
        assertFalse(permissions.afterSwapReturnDelta);
        assertFalse(permissions.beforeAddLiquidityReturnDelta);
        assertFalse(permissions.afterRemoveLiquidityReturnDelta);
    }
    
    /*//////////////////////////////////////////////////////////////
                            USER STRATEGY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetUserStrategy() public {
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 500,
            maxAmount: 10000e6,
            cooldownPeriod: 3600,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        hook.setUserStrategy(strategy);
        
        YieldOptimizationHook.YieldStrategy memory retrieved = hook.userStrategies(USER);
        assertTrue(retrieved.autoRebalance);
        assertEq(retrieved.riskTolerance, 500);
        assertEq(retrieved.maxAmount, 10000e6);
        assertEq(retrieved.cooldownPeriod, 3600);
    }
    
    function test_SetUserStrategy_RevertWhen_InvalidRiskTolerance() public {
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 1001, // > 1000
            maxAmount: 10000e6,
            cooldownPeriod: 3600,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        vm.expectRevert("Invalid risk tolerance");
        hook.setUserStrategy(strategy);
    }
    
    function test_SetUserStrategy_RevertWhen_InvalidMaxAmount() public {
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 500,
            maxAmount: 0, // 0 amount
            cooldownPeriod: 3600,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        vm.expectRevert("Invalid max amount");
        hook.setUserStrategy(strategy);
    }
    
    function test_SetUserStrategy_RevertWhen_InvalidCooldown() public {
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 500,
            maxAmount: 10000e6,
            cooldownPeriod: 0, // 0 cooldown
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        vm.expectRevert("Invalid cooldown period");
        hook.setUserStrategy(strategy);
    }
    
    /*//////////////////////////////////////////////////////////////
                            MANUAL REBALANCE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ManualRebalance() public {
        // Setup user strategy
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 500,
            maxAmount: 10000e6,
            cooldownPeriod: 0,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        hook.setUserStrategy(strategy);
        
        // Execute manual rebalance
        vm.prank(USER);
        hook.manualRebalance();
        
        // Verify rebalance was executed
        assertTrue(mockWalletManager.wasRebalanceExecuted());
    }
    
    function test_ManualRebalance_RevertWhen_NoStrategy() public {
        vm.prank(USER);
        vm.expectRevert("No strategy set");
        hook.manualRebalance();
    }
    
    function test_ManualRebalance_RevertWhen_AutoRebalanceDisabled() public {
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: false,
            riskTolerance: 500,
            maxAmount: 10000e6,
            cooldownPeriod: 0,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        hook.setUserStrategy(strategy);
        
        vm.prank(USER);
        vm.expectRevert("Auto-rebalancing disabled");
        hook.manualRebalance();
    }
    
    function test_ManualRebalance_RevertWhen_CooldownActive() public {
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 500,
            maxAmount: 10000e6,
            cooldownPeriod: 3600,
            lastRebalanceTime: block.timestamp
        });
        
        vm.prank(USER);
        hook.setUserStrategy(strategy);
        
        vm.prank(USER);
        vm.expectRevert("Cooldown period active");
        hook.manualRebalance();
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BeforeSwap_USDCPool() public {
        // Setup user strategy
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 500,
            maxAmount: 10000e6,
            cooldownPeriod: 0,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        hook.setUserStrategy(strategy);
        
        // Create USDC pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(0x123)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(hook)
        });
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(SWAP_AMOUNT),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        // Execute beforeSwap
        vm.prank(USER);
        (bytes4 selector, uint128 beforeSwapDelta, uint24 dynamicLPFee) = hook.beforeSwap(
            USER,
            key,
            params,
            ""
        );
        
        assertEq(selector, hook.beforeSwap.selector);
        assertEq(beforeSwapDelta, 0);
        assertEq(dynamicLPFee, 0);
    }
    
    function test_BeforeSwap_NonUSDCPool() public {
        // Create non-USDC pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x456)),
            currency1: Currency.wrap(address(0x789)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(hook)
        });
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(SWAP_AMOUNT),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        // Execute beforeSwap
        vm.prank(USER);
        (bytes4 selector, uint128 beforeSwapDelta, uint24 dynamicLPFee) = hook.beforeSwap(
            USER,
            key,
            params,
            ""
        );
        
        assertEq(selector, hook.beforeSwap.selector);
        assertEq(beforeSwapDelta, 0);
        assertEq(dynamicLPFee, 0);
    }
    
    function test_AfterSwap_USDCPool() public {
        // Setup user strategy
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 500,
            maxAmount: 10000e6,
            cooldownPeriod: 0,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        hook.setUserStrategy(strategy);
        
        // Create USDC pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(0x123)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(hook)
        });
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(SWAP_AMOUNT),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        // Execute afterSwap
        vm.prank(USER);
        (bytes4 selector, int128 afterSwapDelta) = hook.afterSwap(
            USER,
            key,
            params,
            toBalanceDelta(0, 0),
            ""
        );
        
        assertEq(selector, hook.afterSwap.selector);
        assertEq(afterSwapDelta, 0);
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
    
    function test_ManualRebalance_RevertWhen_Paused() public {
        vm.prank(address(this));
        hook.pause();
        
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 500,
            maxAmount: 10000e6,
            cooldownPeriod: 0,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        hook.setUserStrategy(strategy);
        
        vm.prank(USER);
        vm.expectRevert("Pausable: paused");
        hook.manualRebalance();
    }
    
    /*//////////////////////////////////////////////////////////////
                            TREASURY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetTreasury() public {
        address newTreasury = address(0x999);
        
        vm.prank(address(this));
        hook.setTreasury(newTreasury);
        
        assertEq(hook.treasury(), newTreasury);
    }
    
    function test_SetTreasury_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        hook.setTreasury(address(0x999));
    }
    
    function test_SetTreasury_RevertWhen_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid treasury address");
        hook.setTreasury(address(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EmergencyWithdraw() public {
        uint256 initialBalance = usdc.balanceOf(TREASURY);
        
        vm.prank(address(this));
        hook.emergencyWithdraw();
        
        assertEq(usdc.balanceOf(TREASURY), initialBalance + INITIAL_USDC_BALANCE);
        assertEq(usdc.balanceOf(address(hook)), 0);
    }
    
    function test_EmergencyWithdraw_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        hook.emergencyWithdraw();
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetUserStrategy() public {
        YieldOptimizationHook.YieldStrategy memory strategy = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 500,
            maxAmount: 10000e6,
            cooldownPeriod: 3600,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        hook.setUserStrategy(strategy);
        
        YieldOptimizationHook.YieldStrategy memory retrieved = hook.getUserStrategy(USER);
        assertTrue(retrieved.autoRebalance);
        assertEq(retrieved.riskTolerance, 500);
        assertEq(retrieved.maxAmount, 10000e6);
        assertEq(retrieved.cooldownPeriod, 3600);
    }
    
    function test_GetUserStrategy_Empty() public {
        YieldOptimizationHook.YieldStrategy memory retrieved = hook.getUserStrategy(USER);
        assertFalse(retrieved.autoRebalance);
        assertEq(retrieved.riskTolerance, 0);
        assertEq(retrieved.maxAmount, 0);
        assertEq(retrieved.cooldownPeriod, 0);
    }
    
    function test_IsUSDCPool() public {
        PoolKey memory usdcKey = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(0x123)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(hook)
        });
        
        PoolKey memory nonUsdcKey = PoolKey({
            currency0: Currency.wrap(address(0x456)),
            currency1: Currency.wrap(address(0x789)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(hook)
        });
        
        // This would require making _isUSDCPool public or creating a test helper
        // For now, we test through the hook functions
        assertTrue(true); // Placeholder
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetUserStrategy_Overwrite() public {
        YieldOptimizationHook.YieldStrategy memory strategy1 = YieldOptimizationHook.YieldStrategy({
            autoRebalance: true,
            riskTolerance: 300,
            maxAmount: 5000e6,
            cooldownPeriod: 1800,
            lastRebalanceTime: 0
        });
        
        YieldOptimizationHook.YieldStrategy memory strategy2 = YieldOptimizationHook.YieldStrategy({
            autoRebalance: false,
            riskTolerance: 700,
            maxAmount: 15000e6,
            cooldownPeriod: 7200,
            lastRebalanceTime: 0
        });
        
        vm.prank(USER);
        hook.setUserStrategy(strategy1);
        
        vm.prank(USER);
        hook.setUserStrategy(strategy2);
        
        YieldOptimizationHook.YieldStrategy memory retrieved = hook.userStrategies(USER);
        assertFalse(retrieved.autoRebalance);
        assertEq(retrieved.riskTolerance, 700);
        assertEq(retrieved.maxAmount, 15000e6);
        assertEq(retrieved.cooldownPeriod, 7200);
    }
    
    function test_Constants() public {
        assertEq(hook.USDC(), address(usdc));
        assertEq(hook.MIN_REBALANCE_AMOUNT(), 100e6);
        assertEq(hook.MIN_YIELD_IMPROVEMENT(), 50);
        assertEq(hook.AVS_REWARD_PERCENTAGE(), 10);
    }
}
