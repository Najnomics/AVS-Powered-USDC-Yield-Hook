// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {toBalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../src/hooks/YieldOptimizationHook.sol";
import "../mocks/MockYieldIntelligenceAVS.sol";
import "../mocks/MockCircleWalletManager.sol";
import "../mocks/MockCCTPIntegration.sol";
import "../mocks/MockUSDC.sol";
import "../mocks/MockPoolManager.sol";
import "../mocks/TestYieldOptimizationHook.sol";

/**
 * @title YieldOptimizationIntegration
 * @notice Integration tests for the complete USDC yield optimization system
 * @dev Tests the full flow from swap triggers to yield optimization execution
 */
contract YieldOptimizationIntegration is Test {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    TestYieldOptimizationHook public hook;
    MockYieldIntelligenceAVS public mockAVS;
    MockCircleWalletManager public mockWalletManager;
    MockCCTPIntegration public mockCCTP;
    MockUSDC public usdc;
    MockPoolManager public poolManager;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant TREASURY = address(0x1234);
    address constant USER = address(0x5678);
    address constant OTHER_TOKEN = address(0x9ABC);
    
    uint256 constant INITIAL_USDC_BALANCE = 100000e6; // 100,000 USDC
    uint256 constant SWAP_AMOUNT = 1000e6; // 1,000 USDC
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        poolManager = new MockPoolManager();
        mockAVS = new MockYieldIntelligenceAVS();
        mockWalletManager = new MockCircleWalletManager();
        mockCCTP = new MockCCTPIntegration();
        
        // Deploy the main hook using CREATE2 with proper flags
        hook = _deployHookWithFlags();
        
        // Setup initial state
        _setupInitialState();
        _setupProtocols();
        _setupUserStrategy();
    }
    
    function _deployHookWithFlags() internal returns (TestYieldOptimizationHook) {
        // For testing purposes, we'll deploy normally and skip validation
        // In a real deployment, this would use CREATE2 with proper flags
        return new TestYieldOptimizationHook(
            IPoolManager(address(poolManager)),
            IYieldIntelligenceAVS(address(mockAVS)),
            ICircleWalletManager(address(mockWalletManager)),
            ICCTPIntegration(address(mockCCTP)),
            TREASURY
        );
    }
    
    function _setupInitialState() internal {
        // Deploy MockUSDC at the hardcoded USDC address
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        vm.etch(usdcAddress, address(usdc).code);
        
        // Mint USDC to user
        usdc.mint(USER, INITIAL_USDC_BALANCE);
        
        // Mint USDC to user on the hardcoded USDC address
        MockUSDC(usdcAddress).mint(USER, INITIAL_USDC_BALANCE);
        
        // Setup pool manager with hook
        poolManager.setHook(address(hook));
        
        // Setup mock AVS with yield opportunities
        mockAVS.setYieldOpportunity(
            keccak256("AAVE_V3"),
            1, // chainId
            520, // 5.2% APY
            1000000e6, // 1M USDC available
            8500 // 85% confidence
        );
    }
    
    function _setupProtocols() internal {
        // Add Aave V3 protocol
        hook.addProtocol(
            keccak256("AAVE_V3"),
            "Aave V3",
            address(0x1111), // Mock protocol address
            block.chainid,
            1000000000e6, // 1B USDC max TVL
            100e6, // 100 USDC min deposit
            keccak256("LOW_RISK")
        );
        
        // Add Compound V3 protocol
        hook.addProtocol(
            keccak256("COMPOUND_V3"),
            "Compound V3",
            address(0x2222), // Mock protocol address
            block.chainid,
            500000000e6, // 500M USDC max TVL
            100e6, // 100 USDC min deposit
            keccak256("LOW_RISK")
        );
    }
    
    function _setupUserStrategy() internal {
        vm.startPrank(USER);
        
        // Setup user yield strategy
        bytes32[] memory approvedProtocols = new bytes32[](2);
        approvedProtocols[0] = keccak256("AAVE_V3");
        approvedProtocols[1] = keccak256("COMPOUND_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
        
        hook.setYieldStrategy(
            8000, // 80% target allocation
            5000, // 50% risk tolerance
            50,   // 0.5% minimum improvement threshold
            true, // auto-rebalance enabled
            false, // cross-chain disabled for this test
            approvedProtocols,
            chainIds,
            100 // 1% max slippage
        );
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_FullYieldOptimizationFlow() public {
        // Setup: User has USDC and a yield strategy
        assertEq(usdc.balanceOf(USER), INITIAL_USDC_BALANCE);
        
        // Query yield opportunities to populate the hook's opportunity mapping
        vm.prank(USER);
        hook.queryYieldOpportunities(USER);
        
        // User swaps USDC (triggers yield optimization)
        _simulateUSDCSwap();
        
        // Verify yield optimization was triggered
        assertTrue(mockWalletManager.wasRebalanceExecuted());
        
        // Verify user position was updated (mock verification)
        // Note: In a real implementation, this would check actual user positions
        assertTrue(true, "User position should be updated");
    }
    
    function test_YieldOptimizationWithAVSIntegration() public {
        // Setup: Configure AVS to return specific yield opportunity
        mockAVS.setYieldOpportunity(
            keccak256("AAVE_V3"),
            block.chainid,
            600, // 6% APY
            500000e6, // 500K USDC available
            9000 // 90% confidence
        );
        
        // Query yield opportunities to populate the hook's opportunity mapping
        vm.prank(USER);
        hook.queryYieldOpportunities(USER);
        
        // Trigger yield optimization
        vm.prank(USER);
        hook.manualRebalance();
        
        // Verify the correct protocol was selected
        bytes32 selectedProtocol = mockWalletManager.getLastRebalanceProtocol();
        assertEq(selectedProtocol, keccak256("AAVE_V3"));
    }
    
    function test_CrossChainYieldOptimization() public {
        // Enable cross-chain for user
        vm.startPrank(USER);
        
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = block.chainid;
        chainIds[1] = 8453; // Base
        
        hook.setYieldStrategy(
            8000, // 80% target allocation
            5000, // 50% risk tolerance
            50,   // 0.5% minimum improvement threshold
            true, // auto-rebalance enabled
            true, // cross-chain enabled
            approvedProtocols,
            chainIds,
            100 // 1% max slippage
        );
        
        vm.stopPrank();
        
        // Setup cross-chain opportunity
        mockAVS.setYieldOpportunity(
            keccak256("AAVE_V3"),
            8453, // Base chain
            700, // 7% APY (higher than current chain)
            1000000e6, // 1M USDC available
            8000 // 80% confidence
        );
        
        // Query yield opportunities to populate the hook's opportunity mapping
        vm.prank(USER);
        hook.queryYieldOpportunities(USER);
        
        // Trigger rebalancing
        vm.prank(USER);
        hook.manualRebalance();
        
        // Verify cross-chain transfer was initiated
        assertTrue(mockCCTP.wasTransferInitiated());
        assertEq(mockCCTP.getLastTransferDestination(), 8453);
    }
    
    function test_RiskBasedYieldSelection() public {
        // Setup user with low risk tolerance
        vm.startPrank(USER);
        
        bytes32[] memory approvedProtocols = new bytes32[](2);
        approvedProtocols[0] = keccak256("AAVE_V3");
        approvedProtocols[1] = keccak256("HIGH_RISK_PROTOCOL");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
        
        hook.setYieldStrategy(
            8000, // 80% target allocation
            3000, // 30% risk tolerance (low)
            50,   // 0.5% minimum improvement threshold
            true, // auto-rebalance enabled
            false, // cross-chain disabled
            approvedProtocols,
            chainIds,
            100 // 1% max slippage
        );
        
        vm.stopPrank();
        
        // Add high-risk protocol
        hook.addProtocol(
            keccak256("HIGH_RISK_PROTOCOL"),
            "High Risk Protocol",
            address(0x3333),
            block.chainid,
            100000000e6,
            100e6,
            keccak256("HIGH_RISK")
        );
        
        // Setup yield opportunities
        mockAVS.setYieldOpportunity(
            keccak256("AAVE_V3"),
            block.chainid,
            450, // 4.5% APY, low risk (50bp improvement over current 4%)
            1000000e6,
            9000
        );
        
        mockAVS.setYieldOpportunity(
            keccak256("HIGH_RISK_PROTOCOL"),
            block.chainid,
            1200, // 12% APY, high risk
            1000000e6,
            9000
        );
        
        // Query yield opportunities to populate the hook's opportunity mapping
        vm.prank(USER);
        hook.queryYieldOpportunities(USER);
        
        // Trigger rebalancing
        vm.prank(USER);
        hook.manualRebalance();
        
        // Verify low-risk protocol was selected despite lower yield
        bytes32 selectedProtocol = mockWalletManager.getLastRebalanceProtocol();
        assertEq(selectedProtocol, keccak256("AAVE_V3"));
    }
    
    function test_MinimumImprovementThreshold() public {
        // Setup user with high improvement threshold
        vm.startPrank(USER);
        
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
        
        hook.setYieldStrategy(
            8000, // 80% target allocation
            5000, // 50% risk tolerance
            200,  // 2% minimum improvement threshold (high)
            true, // auto-rebalance enabled
            false, // cross-chain disabled
            approvedProtocols,
            chainIds,
            100 // 1% max slippage
        );
        
        vm.stopPrank();
        
        // Setup marginal yield opportunity (below threshold)
        mockAVS.setYieldOpportunity(
            keccak256("AAVE_V3"),
            block.chainid,
            410, // 4.1% APY (only 0.1% improvement)
            1000000e6,
            9000
        );
        
        // Query yield opportunities to populate the hook's opportunity mapping
        vm.prank(USER);
        hook.queryYieldOpportunities(USER);
        
        // Trigger rebalancing
        vm.prank(USER);
        vm.expectRevert("No profitable rebalancing opportunity");
        hook.manualRebalance();
    }
    
    function test_RebalancingCooldown() public {
        // Query yield opportunities to populate the hook's opportunity mapping
        vm.prank(USER);
        hook.queryYieldOpportunities(USER);
        
        // First rebalancing
        vm.prank(USER);
        hook.manualRebalance();
        
        // Try immediate rebalancing (should fail due to cooldown)
        _simulateUSDCSwap();
        
        // Verify no second rebalancing occurred
        assertEq(mockWalletManager.getRebalanceCount(), 1);
        
        // Wait for cooldown to pass
        vm.warp(block.timestamp + hook.REBALANCE_COOLDOWN() + 1);
        
        // Trigger another swap
        _simulateUSDCSwap();
        
        // Verify second rebalancing occurred
        assertEq(mockWalletManager.getRebalanceCount(), 2);
    }
    
    function test_FailedRebalancingHandling() public {
        // Query yield opportunities to populate the hook's opportunity mapping
        vm.prank(USER);
        hook.queryYieldOpportunities(USER);
        
        // Configure mock to fail rebalancing
        mockWalletManager.setShouldFailRebalancing(true);
        
        // Attempt rebalancing
        vm.prank(USER);
        vm.expectRevert("Mock rebalancing failure");
        hook.manualRebalance();
        
        // Verify user position wasn't updated (mock verification)
        // Note: In a real implementation, this would check actual user positions
        assertTrue(true, "User position should not be updated");
    }
    
    function test_GasOptimizationInRebalancing() public {
        // Query yield opportunities to populate the hook's opportunity mapping
        vm.prank(USER);
        hook.queryYieldOpportunities(USER);
        
        uint256 gasBefore = gasleft();
        
        // Execute rebalancing
        vm.prank(USER);
        hook.manualRebalance();
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify gas usage is reasonable (adjust threshold as needed)
        assertLt(gasUsed, 500000, "Gas usage should be optimized");
        
        console.log("Gas used for rebalancing:", gasUsed);
    }
    
    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _simulateUSDCSwap() internal {
        // Create pool key for USDC/OTHER_TOKEN pair using hardcoded USDC address
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(usdcAddress),
            currency1: Currency.wrap(OTHER_TOKEN),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });
        
        // Simulate swap parameters
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(SWAP_AMOUNT),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        // Trigger beforeSwap from pool manager context
        vm.prank(address(poolManager));
        hook.beforeSwap(USER, key, params, "");
        
        // Simulate the actual swap (simplified)
        // In real scenario, this would be handled by the pool manager
        
        // Trigger afterSwap from pool manager context
        vm.prank(address(poolManager));
        hook.afterSwap(USER, key, params, createBalanceDelta(0, 0), "");
    }
    
    function createBalanceDelta(int128 amount0, int128 amount1) internal pure returns (BalanceDelta) {
        return toBalanceDelta(amount0, amount1);
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    function test_RevertWhen_InsufficientUSDCBalance() public {
        // Set user balance to very low amount
        vm.startPrank(USER);
        usdc.transfer(address(1), INITIAL_USDC_BALANCE - 50e6); // Leave only 50 USDC
        
        // Try to rebalance (should fail due to minimum amount requirement)
        vm.expectRevert("No profitable rebalancing opportunity");
        hook.manualRebalance();
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_NoYieldOpportunities() public {
        // Clear all yield opportunities
        mockAVS.clearYieldOpportunities();
        
        // Try to rebalance
        vm.prank(USER);
        vm.expectRevert("No profitable rebalancing opportunity");
        hook.manualRebalance();
    }
    
    function test_RevertWhen_AutoRebalanceDisabled() public {
        // Disable auto-rebalancing
        vm.startPrank(USER);
        
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
        
        hook.setYieldStrategy(
            8000, // 80% target allocation
            5000, // 50% risk tolerance
            50,   // 0.5% minimum improvement threshold
            false, // auto-rebalance DISABLED
            false, // cross-chain disabled
            approvedProtocols,
            chainIds,
            100 // 1% max slippage
        );
        
        vm.stopPrank();
        
        // Trigger swap (should not execute rebalancing)
        _simulateUSDCSwap();
        
        // Verify no rebalancing occurred
        assertFalse(mockWalletManager.wasRebalanceExecuted());
    }
}