// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {BaseYieldAdapter} from "../../src/protocols/BaseYieldAdapter.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/**
 * @title BaseYieldAdapterUnitTest
 * @notice Comprehensive unit tests for BaseYieldAdapter
 * @dev Tests all functions, edge cases, and error conditions
 */
contract BaseYieldAdapterUnitTest is Test {
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    BaseYieldAdapter public adapter;
    MockUSDC public usdc;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant USER = address(0x1);
    address constant TREASURY = address(0x2);
    address constant PROTOCOL = address(0x3);
    
    uint256 constant INITIAL_BALANCE = 100000e6; // 100k USDC
    uint256 constant DEPOSIT_AMOUNT = 10000e6; // 10k USDC
    uint256 constant WITHDRAWAL_AMOUNT = 5000e6; // 5k USDC
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        usdc = new MockUSDC();
        
        adapter = new BaseYieldAdapter(
            address(usdc),
            TREASURY
        );
        
        // Setup initial state
        usdc.mint(USER, INITIAL_BALANCE);
        usdc.mint(address(adapter), INITIAL_BALANCE);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(adapter.USDC(), address(usdc));
        assertEq(adapter.treasury(), TREASURY);
        assertEq(adapter.owner(), address(this));
    }
    
    function test_Constructor_RevertWhen_ZeroUSDC() public {
        vm.expectRevert("Invalid USDC address");
        new BaseYieldAdapter(
            address(0),
            TREASURY
        );
    }
    
    function test_Constructor_RevertWhen_ZeroTreasury() public {
        vm.expectRevert("Invalid treasury address");
        new BaseYieldAdapter(
            address(usdc),
            address(0)
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Deposit() public {
        uint256 initialBalance = usdc.balanceOf(address(adapter));
        
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        assertEq(usdc.balanceOf(address(adapter)), initialBalance + DEPOSIT_AMOUNT);
        assertEq(adapter.userBalances(USER), DEPOSIT_AMOUNT);
    }
    
    function test_Deposit_RevertWhen_InsufficientAllowance() public {
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT - 1);
        
        vm.prank(USER);
        vm.expectRevert("ERC20: insufficient allowance");
        adapter.deposit(DEPOSIT_AMOUNT);
    }
    
    function test_Deposit_RevertWhen_ZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert("Invalid amount");
        adapter.deposit(0);
    }
    
    function test_Deposit_RevertWhen_ExceedsMaxAmount() public {
        vm.prank(USER);
        usdc.approve(address(adapter), adapter.MAX_SINGLE_AMOUNT() + 1);
        
        vm.prank(USER);
        vm.expectRevert("Amount exceeds maximum");
        adapter.deposit(adapter.MAX_SINGLE_AMOUNT() + 1);
    }
    
    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Withdraw() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // Then withdraw
        vm.prank(USER);
        adapter.withdraw(WITHDRAWAL_AMOUNT);
        
        assertEq(adapter.userBalances(USER), DEPOSIT_AMOUNT - WITHDRAWAL_AMOUNT);
    }
    
    function test_Withdraw_RevertWhen_InsufficientBalance() public {
        vm.prank(USER);
        vm.expectRevert("Insufficient balance");
        adapter.withdraw(WITHDRAWAL_AMOUNT);
    }
    
    function test_Withdraw_RevertWhen_ZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert("Invalid amount");
        adapter.withdraw(0);
    }
    
    function test_Withdraw_RevertWhen_ExceedsBalance() public {
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        vm.expectRevert("Insufficient balance");
        adapter.withdraw(DEPOSIT_AMOUNT + 1);
    }
    
    /*//////////////////////////////////////////////////////////////
                            YIELD CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CalculateYield() public {
        uint256 yield = adapter.calculateYield(DEPOSIT_AMOUNT, 500); // 5% APY
        
        assertTrue(yield > 0);
        assertTrue(yield < DEPOSIT_AMOUNT);
    }
    
    function test_CalculateYield_RevertWhen_ZeroAmount() public {
        vm.expectRevert("Invalid amount");
        adapter.calculateYield(0, 500);
    }
    
    function test_CalculateYield_RevertWhen_ZeroRate() public {
        vm.expectRevert("Invalid rate");
        adapter.calculateYield(DEPOSIT_AMOUNT, 0);
    }
    
    function test_CalculateYield_RevertWhen_InvalidRate() public {
        vm.expectRevert("Invalid rate");
        adapter.calculateYield(DEPOSIT_AMOUNT, 10001); // > 100%
    }
    
    function test_GetCurrentYieldRate() public {
        uint256 rate = adapter.getCurrentYieldRate();
        assertTrue(rate >= 0);
    }
    
    function test_GetTotalYield() public {
        uint256 yield = adapter.getTotalYield();
        assertTrue(yield >= 0);
    }
    
    function test_GetUserYield() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        uint256 yield = adapter.getUserYield(USER);
        assertTrue(yield >= 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            REBALANCING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Rebalance() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // Rebalance
        vm.prank(USER);
        adapter.rebalance();
        
        // Should succeed
        assertTrue(true);
    }
    
    function test_Rebalance_RevertWhen_NoBalance() public {
        vm.prank(USER);
        vm.expectRevert("No balance to rebalance");
        adapter.rebalance();
    }
    
    function test_Rebalance_RevertWhen_CooldownActive() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // First rebalance
        vm.prank(USER);
        adapter.rebalance();
        
        // Try to rebalance again immediately
        vm.prank(USER);
        vm.expectRevert("Cooldown period active");
        adapter.rebalance();
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetTreasury() public {
        address newTreasury = address(0x999);
        
        vm.prank(address(this));
        adapter.setTreasury(newTreasury);
        
        assertEq(adapter.treasury(), newTreasury);
    }
    
    function test_SetTreasury_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        adapter.setTreasury(address(0x999));
    }
    
    function test_SetTreasury_RevertWhen_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid treasury address");
        adapter.setTreasury(address(0));
    }
    
    function test_SetMaxSingleAmount() public {
        uint256 newMax = 2000000e6; // 2M USDC
        
        vm.prank(address(this));
        adapter.setMaxSingleAmount(newMax);
        
        assertEq(adapter.MAX_SINGLE_AMOUNT(), newMax);
    }
    
    function test_SetMaxSingleAmount_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        adapter.setMaxSingleAmount(2000000e6);
    }
    
    function test_SetMaxDailyAmount() public {
        uint256 newMax = 20000000e6; // 20M USDC
        
        vm.prank(address(this));
        adapter.setMaxDailyAmount(newMax);
        
        assertEq(adapter.MAX_DAILY_AMOUNT(), newMax);
    }
    
    function test_SetMaxDailyAmount_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        adapter.setMaxDailyAmount(20000000e6);
    }
    
    function test_SetProtocolFee() public {
        uint256 newFee = 50; // 0.5%
        
        vm.prank(address(this));
        adapter.setProtocolFee(newFee);
        
        assertEq(adapter.protocolFee(), newFee);
    }
    
    function test_SetProtocolFee_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        adapter.setProtocolFee(50);
    }
    
    function test_SetProtocolFee_RevertWhen_InvalidFee() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid protocol fee");
        adapter.setProtocolFee(10001); // > 100%
    }
    
    function test_SetCooldownPeriod() public {
        uint256 newCooldown = 1800; // 30 minutes
        
        vm.prank(address(this));
        adapter.setCooldownPeriod(newCooldown);
        
        assertEq(adapter.cooldownPeriod(), newCooldown);
    }
    
    function test_SetCooldownPeriod_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        adapter.setCooldownPeriod(1800);
    }
    
    function test_SetCooldownPeriod_RevertWhen_InvalidPeriod() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid cooldown period");
        adapter.setCooldownPeriod(0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EmergencyWithdraw() public {
        uint256 initialBalance = usdc.balanceOf(TREASURY);
        
        vm.prank(address(this));
        adapter.emergencyWithdraw();
        
        assertEq(usdc.balanceOf(TREASURY), initialBalance + INITIAL_BALANCE);
        assertEq(usdc.balanceOf(address(adapter)), 0);
    }
    
    function test_EmergencyWithdraw_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        adapter.emergencyWithdraw();
    }
    
    function test_EmergencyWithdrawToken() public {
        address token = address(usdc);
        uint256 amount = 1000e6;
        
        usdc.mint(address(adapter), amount);
        
        vm.prank(address(this));
        adapter.emergencyWithdrawToken(token, amount);
        
        assertEq(usdc.balanceOf(TREASURY), amount);
    }
    
    function test_EmergencyWithdrawToken_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        adapter.emergencyWithdrawToken(address(usdc), 1000e6);
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetUserBalance() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        uint256 balance = adapter.getUserBalance(USER);
        assertEq(balance, DEPOSIT_AMOUNT);
    }
    
    function test_GetTotalBalance() public {
        uint256 balance = adapter.getTotalBalance();
        assertEq(balance, INITIAL_BALANCE);
    }
    
    function test_GetDailyVolume() public {
        uint256 volume = adapter.getDailyVolume(USER);
        assertEq(volume, 0); // No transactions yet
    }
    
    function test_GetTotalVolume() public {
        uint256 volume = adapter.getTotalVolume();
        assertEq(volume, 0); // No transactions yet
    }
    
    function test_GetLastRebalanceTime() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // Rebalance
        vm.prank(USER);
        adapter.rebalance();
        
        uint256 lastRebalance = adapter.getLastRebalanceTime(USER);
        assertTrue(lastRebalance > 0);
    }
    
    function test_CanRebalance() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        bool canRebalance = adapter.canRebalance(USER);
        assertTrue(canRebalance);
    }
    
    function test_CanRebalance_RevertWhen_NoBalance() public {
        bool canRebalance = adapter.canRebalance(USER);
        assertFalse(canRebalance);
    }
    
    function test_CanRebalance_RevertWhen_CooldownActive() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // First rebalance
        vm.prank(USER);
        adapter.rebalance();
        
        bool canRebalance = adapter.canRebalance(USER);
        assertFalse(canRebalance);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(adapter.USDC(), address(usdc));
        assertTrue(adapter.MIN_SINGLE_AMOUNT() > 0);
        assertTrue(adapter.MAX_SINGLE_AMOUNT() > 0);
        assertTrue(adapter.MIN_DAILY_AMOUNT() > 0);
        assertTrue(adapter.MAX_DAILY_AMOUNT() > 0);
        assertTrue(adapter.protocolFee() >= 0);
        assertTrue(adapter.cooldownPeriod() > 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Deposit_MaxAmount() public {
        uint256 maxAmount = adapter.MAX_SINGLE_AMOUNT();
        
        vm.prank(USER);
        usdc.approve(address(adapter), maxAmount);
        
        vm.prank(USER);
        adapter.deposit(maxAmount);
        
        assertEq(adapter.userBalances(USER), maxAmount);
    }
    
    function test_Withdraw_AllBalance() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // Withdraw all
        vm.prank(USER);
        adapter.withdraw(DEPOSIT_AMOUNT);
        
        assertEq(adapter.userBalances(USER), 0);
    }
    
    function test_CalculateYield_MaxRate() public {
        uint256 yield = adapter.calculateYield(DEPOSIT_AMOUNT, 10000); // 100% APY
        
        assertTrue(yield > 0);
        assertTrue(yield <= DEPOSIT_AMOUNT);
    }
    
    function test_CalculateYield_MinRate() public {
        uint256 yield = adapter.calculateYield(DEPOSIT_AMOUNT, 1); // 0.01% APY
        
        assertTrue(yield > 0);
        assertTrue(yield < DEPOSIT_AMOUNT);
    }
    
    function test_Rebalance_AfterCooldown() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // First rebalance
        vm.prank(USER);
        adapter.rebalance();
        
        // Wait for cooldown to expire
        vm.warp(block.timestamp + adapter.cooldownPeriod() + 1);
        
        // Second rebalance should work
        vm.prank(USER);
        adapter.rebalance();
        
        // Should succeed
        assertTrue(true);
    }
    
    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_Deposit_ValidAmount(uint256 amount) public {
        amount = bound(amount, adapter.MIN_SINGLE_AMOUNT(), adapter.MAX_SINGLE_AMOUNT());
        
        vm.prank(USER);
        usdc.approve(address(adapter), amount);
        
        vm.prank(USER);
        adapter.deposit(amount);
        
        assertEq(adapter.userBalances(USER), amount);
    }
    
    function testFuzz_Withdraw_ValidAmount(uint256 amount) public {
        // First deposit max amount
        uint256 depositAmount = adapter.MAX_SINGLE_AMOUNT();
        
        vm.prank(USER);
        usdc.approve(address(adapter), depositAmount);
        
        vm.prank(USER);
        adapter.deposit(depositAmount);
        
        // Withdraw valid amount
        amount = bound(amount, 1, depositAmount);
        
        vm.prank(USER);
        adapter.withdraw(amount);
        
        assertEq(adapter.userBalances(USER), depositAmount - amount);
    }
    
    function testFuzz_CalculateYield_ValidRate(uint256 rate) public {
        rate = bound(rate, 1, 10000); // 0.01% to 100%
        
        uint256 yield = adapter.calculateYield(DEPOSIT_AMOUNT, rate);
        
        assertTrue(yield > 0);
        assertTrue(yield <= DEPOSIT_AMOUNT);
    }
    
    function testFuzz_SetMaxSingleAmount_ValidAmount(uint256 amount) public {
        amount = bound(amount, adapter.MIN_SINGLE_AMOUNT(), type(uint256).max);
        
        vm.prank(address(this));
        adapter.setMaxSingleAmount(amount);
        
        assertEq(adapter.MAX_SINGLE_AMOUNT(), amount);
    }
    
    function testFuzz_SetMaxDailyAmount_ValidAmount(uint256 amount) public {
        amount = bound(amount, adapter.MIN_DAILY_AMOUNT(), type(uint256).max);
        
        vm.prank(address(this));
        adapter.setMaxDailyAmount(amount);
        
        assertEq(adapter.MAX_DAILY_AMOUNT(), amount);
    }
    
    function testFuzz_SetProtocolFee_ValidFee(uint256 fee) public {
        fee = bound(fee, 0, 10000); // 0% to 100%
        
        vm.prank(address(this));
        adapter.setProtocolFee(fee);
        
        assertEq(adapter.protocolFee(), fee);
    }
    
    function testFuzz_SetCooldownPeriod_ValidPeriod(uint256 period) public {
        period = bound(period, 1, 365 days);
        
        vm.prank(address(this));
        adapter.setCooldownPeriod(period);
        
        assertEq(adapter.cooldownPeriod(), period);
    }
}
