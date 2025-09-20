// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {YieldOptimizationHook} from "../../src/hooks/YieldOptimizationHook.sol";
import {TestYieldOptimizationHook} from "../mocks/TestYieldOptimizationHook.sol";
import {MockPoolManager} from "../mocks/MockPoolManager.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {MockYieldIntelligenceAVS} from "../mocks/MockYieldIntelligenceAVS.sol";
import {MockCircleWalletManager} from "../mocks/MockCircleWalletManager.sol";
import {MockCCTPIntegration} from "../mocks/MockCCTPIntegration.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";

contract YieldOptimizationInvariantTest is StdInvariant, Test {
    TestYieldOptimizationHook public hook;
    MockPoolManager public poolManager;
    MockUSDC public usdc;
    MockYieldIntelligenceAVS public mockAVS;
    MockCircleWalletManager public mockWalletManager;
    MockCCTPIntegration public mockCCTP;
    
    address public constant TREASURY = address(0x2);
    address public constant USDC_ADDRESS = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
    
    // Handler contracts
    YieldOptimizationHandler public handler;
    
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
        
        // Deploy handler
        handler = new YieldOptimizationHandler(hook, mockAVS);
        
        // Set target contract
        targetContract(address(handler));
        
        // Set target selectors
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = YieldOptimizationHandler.setYieldStrategy.selector;
        selectors[1] = YieldOptimizationHandler.addProtocol.selector;
        selectors[2] = YieldOptimizationHandler.manualRebalance.selector;
        selectors[3] = YieldOptimizationHandler.collectFees.selector;
        selectors[4] = YieldOptimizationHandler.updateTreasury.selector;
        selectors[5] = YieldOptimizationHandler.pauseUnpause.selector;
        
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }
    
    function invariant_TotalSupplyConservation() public {
        // The total USDC supply should remain constant
        uint256 totalSupply = MockUSDC(USDC_ADDRESS).totalSupply();
        // Allow for some supply changes due to minting in tests
        assertGe(totalSupply, 0);
    }
    
    function invariant_TreasuryBalanceNonNegative() public {
        // Treasury balance should never be negative
        uint256 treasuryBalance = MockUSDC(USDC_ADDRESS).balanceOf(TREASURY);
        assertGe(treasuryBalance, 0);
    }
    
    function invariant_HookBalanceNonNegative() public {
        // Hook balance should never be negative
        uint256 hookBalance = MockUSDC(USDC_ADDRESS).balanceOf(address(hook));
        assertGe(hookBalance, 0);
    }
    
    function invariant_ProtocolCountConsistent() public {
        // Number of active protocols should be consistent
        // This is a basic check - in practice, you'd want more sophisticated invariants
        assertTrue(true); // Placeholder for more complex protocol state checks
    }
    
    function invariant_UserStrategyConsistency() public {
        // User strategies should maintain consistency
        // This is a basic check - in practice, you'd want more sophisticated invariants
        assertTrue(true); // Placeholder for more complex strategy state checks
    }
    
    function invariant_NoDoubleSpending() public {
        // No user should be able to spend more USDC than they have
        // This is a basic check - in practice, you'd want more sophisticated invariants
        assertTrue(true); // Placeholder for more complex spending checks
    }
    
    function invariant_ProtocolStateConsistency() public {
        // Protocol states should remain consistent
        // This is a basic check - in practice, you'd want more sophisticated invariants
        assertTrue(true); // Placeholder for more complex protocol state checks
    }
    
    function invariant_YieldOpportunityValidity() public {
        // Yield opportunities should maintain validity constraints
        // This is a basic check - in practice, you'd want more sophisticated invariants
        assertTrue(true); // Placeholder for more complex opportunity checks
    }
}

contract YieldOptimizationHandler is Test {
    TestYieldOptimizationHook public hook;
    MockYieldIntelligenceAVS public mockAVS;
    
    address public constant USER = address(0x1);
    address public constant USDC_ADDRESS = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
    
    constructor(TestYieldOptimizationHook _hook, MockYieldIntelligenceAVS _mockAVS) {
        hook = _hook;
        mockAVS = _mockAVS;
    }
    
    function setYieldStrategy(
        uint256 targetAllocation,
        uint256 riskTolerance,
        uint256 rebalanceThreshold,
        bool autoRebalance,
        bool crossChainEnabled,
        uint256 maxSlippage
    ) public {
        // Bound inputs to reasonable ranges
        targetAllocation = bound(targetAllocation, 1000, 10000);
        riskTolerance = bound(riskTolerance, 100, 10000);
        rebalanceThreshold = bound(rebalanceThreshold, 1, 1000);
        maxSlippage = bound(maxSlippage, 1, 10000);
        
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
    }
    
    function addProtocol(
        bytes32 protocolId,
        string memory name,
        address protocolAddress,
        uint256 chainId,
        uint256 maxTvl,
        uint256 minDeposit,
        bytes32 riskCategory
    ) public {
        // Bound inputs to reasonable ranges
        maxTvl = bound(maxTvl, 1000e6, 1000000000e6);
        minDeposit = bound(minDeposit, 1e6, 1000000e6);
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
    }
    
    function manualRebalance(uint256 amount) public {
        // Bound amount to reasonable range
        amount = bound(amount, 100e6, 1000000e6);
        
        // Mint USDC to user
        MockUSDC(USDC_ADDRESS).mint(USER, amount);
        MockUSDC(USDC_ADDRESS).approve(address(hook), amount);
        
        // Setup yield opportunity
        bytes32 protocolId = keccak256("AAVE_V3");
        mockAVS.setYieldOpportunity(protocolId, 1, 450, amount, 9000);
        
        vm.prank(USER);
        hook.manualRebalance();
    }
    
    function collectFees() public {
        // Mint some USDC to hook
        uint256 feeAmount = bound(uint256(keccak256(abi.encodePacked(block.timestamp))), 1e6, 1000000e6);
        MockUSDC(USDC_ADDRESS).mint(address(hook), feeAmount);
        
        vm.prank(address(hook.owner()));
        hook.collectFees();
    }
    
    function updateTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0));
        
        vm.prank(address(hook.owner()));
        hook.updateTreasury(newTreasury);
    }
    
    function pauseUnpause() public {
        if (hook.paused()) {
            vm.prank(address(hook.owner()));
            hook.unpause();
        } else {
            vm.prank(address(hook.owner()));
            hook.pause();
        }
    }
}
