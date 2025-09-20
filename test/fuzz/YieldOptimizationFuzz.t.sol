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

contract YieldOptimizationFuzzTest is Test {
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
    
    function testFuzz_SetYieldStrategy(
        uint256 targetAllocation,
        uint256 riskTolerance,
        uint256 rebalanceThreshold,
        bool autoRebalance,
        bool crossChainEnabled,
        uint256 maxSlippage
    ) public {
        // Bound inputs to reasonable ranges
        targetAllocation = bound(targetAllocation, 1000, 10000); // 10% to 100%
        riskTolerance = bound(riskTolerance, 100, 10000); // 1% to 100%
        rebalanceThreshold = bound(rebalanceThreshold, 1, 1000); // 0.01% to 10%
        maxSlippage = bound(maxSlippage, 1, 1000); // 0.01% to 10% (max 10% slippage)
        
        bytes32[] memory approvedProtocols = new bytes32[](1);
        approvedProtocols[0] = keccak256("AAVE_V3");
        
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 1;
        
        vm.prank(USER);
        hook.setYieldStrategy(
            targetAllocation,
            riskTolerance,
            rebalanceThreshold,
            autoRebalance,
            crossChainEnabled,
            approvedProtocols,
            chainIds,
            maxSlippage
        );
        
        // Verify strategy was set
        (uint256 allocation, uint256 risk, uint256 threshold, bool autoRebalanceFlag, bool crossChainFlag, uint256 slippage) = 
            hook.userStrategies(USER);
        
        assertEq(allocation, targetAllocation);
        assertEq(risk, riskTolerance);
        assertEq(threshold, rebalanceThreshold);
        assertEq(autoRebalanceFlag, autoRebalance);
        assertEq(crossChainFlag, crossChainEnabled);
        assertEq(slippage, maxSlippage);
    }
    
    function testFuzz_AddProtocol(
        bytes32 protocolId,
        string memory name,
        address protocolAddress,
        uint256 chainId,
        uint256 maxTvl,
        uint256 minDeposit,
        bytes32 riskCategory
    ) public {
        // Bound inputs to reasonable ranges
        maxTvl = bound(maxTvl, 1000e6, 1000000000e6); // 1K to 1B USDC
        minDeposit = bound(minDeposit, 1e6, 1000000e6); // 1 to 1M USDC
        chainId = bound(chainId, 1, 1000);
        
        vm.prank(address(hook.owner()));
        hook.addProtocol(
            protocolId,
            name,
            protocolAddress,
            chainId,
            maxTvl,
            minDeposit,
            riskCategory
        );
        
        // Verify protocol was added
        (string memory protocolName, address addr, uint256 cid, bool isActive, uint256 tvl, uint256 minDep, bytes32 riskCat) = 
            hook.supportedProtocols(protocolId);
        
        assertEq(protocolName, name);
        assertEq(addr, protocolAddress);
        assertEq(cid, chainId);
        assertEq(tvl, maxTvl);
        assertEq(minDep, minDeposit);
        assertTrue(isActive);
    }
    
    function testFuzz_ManualRebalance(uint256 amount) public {
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
            5000, // targetAllocation
            3000, // riskTolerance
            50,   // rebalanceThreshold
            true, // autoRebalance
            true, // crossChainEnabled
            approvedProtocols,
            chainIds,
            100   // maxSlippage
        );
        
        // Bound amount to reasonable range
        amount = bound(amount, 100e6, 1000000e6);
        
        // Setup yield opportunity with higher yield than current
        mockAVS.setYieldOpportunity(
            protocolId,
            block.chainid, // Use current chain ID
            500, // 5% APY (higher than current 4%)
            amount,
            9000 // 90% confidence
        );
        
        // Mint USDC to user
        MockUSDC(USDC_ADDRESS).mint(USER, amount);
        MockUSDC(USDC_ADDRESS).approve(address(hook), amount);
        
        // Query yield opportunities first to populate them
        hook.queryYieldOpportunities(USER);
        
        // Execute manual rebalance
        vm.prank(USER);
        hook.manualRebalance();
        
        // Verify rebalancing was executed
        assertTrue(mockWalletManager.wasRebalanceExecuted());
    }
    
    function testFuzz_CollectFees(uint256 feeAmount) public {
        // Bound fee amount
        feeAmount = bound(feeAmount, 1e6, 1000000e6);
        
        // Get initial treasury balance
        uint256 initialTreasuryBalance = MockUSDC(USDC_ADDRESS).balanceOf(TREASURY);
        
        // Get initial hook balance
        uint256 initialHookBalance = MockUSDC(USDC_ADDRESS).balanceOf(address(hook));
        
        // Mint additional USDC to hook
        MockUSDC(USDC_ADDRESS).mint(address(hook), feeAmount);
        
        // Collect fees
        vm.prank(address(hook.owner()));
        hook.collectFees();
        
        // Verify fees were collected (treasury should have the total hook balance)
        assertEq(MockUSDC(USDC_ADDRESS).balanceOf(TREASURY), initialTreasuryBalance + initialHookBalance + feeAmount);
        
        // Verify hook balance is now zero (all fees collected)
        assertEq(MockUSDC(USDC_ADDRESS).balanceOf(address(hook)), 0);
    }
    
    function testFuzz_UpdateTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0));
        vm.assume(newTreasury != TREASURY);
        
        vm.prank(address(hook.owner()));
        hook.updateTreasury(newTreasury);
        
        assertEq(hook.treasury(), newTreasury);
    }
    
    function testFuzz_PauseUnpause() public {
        // Test pause
        vm.prank(address(hook.owner()));
        hook.pause();
        assertTrue(hook.paused());
        
        // Test unpause
        vm.prank(address(hook.owner()));
        hook.unpause();
        assertFalse(hook.paused());
    }
    
    function testFuzz_RebalancingCooldown(uint256 cooldownTime) public {
        // Bound cooldown time to be at least the minimum cooldown
        cooldownTime = bound(cooldownTime, 3600, 86400); // 1 hour to 24 hours
        
        // Setup protocol and strategy
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
        
        // First rebalance should succeed
        MockUSDC(USDC_ADDRESS).mint(USER, 1000e6);
        MockUSDC(USDC_ADDRESS).approve(address(hook), 1000e6);
        
        // Query yield opportunities first
        hook.queryYieldOpportunities(USER);
        
        vm.prank(USER);
        hook.manualRebalance();
        
        // Fast forward by cooldown time
        vm.warp(block.timestamp + cooldownTime);
        
        // Refresh yield opportunity after time warp to ensure it's still valid
        mockAVS.setYieldOpportunity(protocolId, block.chainid, 500, 1000000e6, 9000);
        
        // Second rebalance should succeed if cooldown has passed
        MockUSDC(USDC_ADDRESS).mint(USER, 1000e6);
        MockUSDC(USDC_ADDRESS).approve(address(hook), 1000e6);
        
        // Query yield opportunities again
        hook.queryYieldOpportunities(USER);
        
        vm.prank(USER);
        hook.manualRebalance();
        
        // Should have executed twice
        assertTrue(mockWalletManager.wasRebalanceExecuted());
    }
}
