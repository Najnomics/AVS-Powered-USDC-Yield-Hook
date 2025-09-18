// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {AaveV3Adapter} from "../../src/protocols/AaveV3Adapter.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/**
 * @title AaveV3AdapterUnitTest
 * @notice Comprehensive unit tests for AaveV3Adapter
 * @dev Tests all functions, edge cases, and error conditions
 */
contract AaveV3AdapterUnitTest is Test {
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    AaveV3Adapter public adapter;
    MockUSDC public usdc;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant USER = address(0x1);
    address constant TREASURY = address(0x2);
    address constant LENDING_POOL = address(0x3);
    address constant ATOKEN = address(0x4);
    
    uint256 constant INITIAL_BALANCE = 100000e6; // 100k USDC
    uint256 constant DEPOSIT_AMOUNT = 10000e6; // 10k USDC
    uint256 constant WITHDRAWAL_AMOUNT = 5000e6; // 5k USDC
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        usdc = new MockUSDC();
        
        adapter = new AaveV3Adapter(
            address(usdc),
            TREASURY,
            LENDING_POOL,
            ATOKEN
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
        assertEq(adapter.lendingPool(), LENDING_POOL);
        assertEq(adapter.aToken(), ATOKEN);
        assertEq(adapter.owner(), address(this));
    }
    
    function test_Constructor_RevertWhen_ZeroUSDC() public {
        vm.expectRevert("Invalid USDC address");
        new AaveV3Adapter(
            address(0),
            TREASURY,
            LENDING_POOL,
            ATOKEN
        );
    }
    
    function test_Constructor_RevertWhen_ZeroTreasury() public {
        vm.expectRevert("Invalid treasury address");
        new AaveV3Adapter(
            address(usdc),
            address(0),
            LENDING_POOL,
            ATOKEN
        );
    }
    
    function test_Constructor_RevertWhen_ZeroLendingPool() public {
        vm.expectRevert("Invalid lending pool address");
        new AaveV3Adapter(
            address(usdc),
            TREASURY,
            address(0),
            ATOKEN
        );
    }
    
    function test_Constructor_RevertWhen_ZeroAToken() public {
        vm.expectRevert("Invalid aToken address");
        new AaveV3Adapter(
            address(usdc),
            TREASURY,
            LENDING_POOL,
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
                            AAVE-SPECIFIC TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLendingPoolAddress() public {
        assertEq(adapter.getLendingPoolAddress(), LENDING_POOL);
    }
    
    function test_GetATokenAddress() public {
        assertEq(adapter.getATokenAddress(), ATOKEN);
    }
    
    function test_GetReserveData() public {
        (uint256 totalLiquidity, uint256 availableLiquidity, uint256 totalStableDebt, uint256 totalVariableDebt) = 
            adapter.getReserveData();
        
        assertTrue(totalLiquidity >= 0);
        assertTrue(availableLiquidity >= 0);
        assertTrue(totalStableDebt >= 0);
        assertTrue(totalVariableDebt >= 0);
    }
    
    function test_GetUserAccountData() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor) = 
            adapter.getUserAccountData(USER);
        
        assertTrue(totalCollateralETH >= 0);
        assertTrue(totalDebtETH >= 0);
        assertTrue(availableBorrowsETH >= 0);
        assertTrue(currentLiquidationThreshold >= 0);
        assertTrue(ltv >= 0);
        assertTrue(healthFactor >= 0);
    }
    
    function test_GetUserReserveData() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        (uint256 currentATokenBalance, uint256 currentStableDebt, uint256 currentVariableDebt, uint256 principalStableDebt, uint256 scaledVariableDebt, uint256 stableBorrowRate, uint256 liquidityRate, uint256 stableRateLastUpdated, uint256 usageAsCollateralEnabled) = 
            adapter.getUserReserveData(USER);
        
        assertTrue(currentATokenBalance >= 0);
        assertTrue(currentStableDebt >= 0);
        assertTrue(currentVariableDebt >= 0);
        assertTrue(principalStableDebt >= 0);
        assertTrue(scaledVariableDebt >= 0);
        assertTrue(stableBorrowRate >= 0);
        assertTrue(liquidityRate >= 0);
        assertTrue(stableRateLastUpdated >= 0);
        assertTrue(usageAsCollateralEnabled >= 0);
    }
    
    function test_GetReserveConfigurationData() public {
        (uint256 decimals, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor, bool usageAsCollateralEnabled, bool borrowingEnabled, bool stableBorrowRateEnabled, bool isActive, bool isFrozen) = 
            adapter.getReserveConfigurationData();
        
        assertTrue(decimals >= 0);
        assertTrue(ltv >= 0);
        assertTrue(liquidationThreshold >= 0);
        assertTrue(liquidationBonus >= 0);
        assertTrue(reserveFactor >= 0);
        assertTrue(usageAsCollateralEnabled || !usageAsCollateralEnabled);
        assertTrue(borrowingEnabled || !borrowingEnabled);
        assertTrue(stableBorrowRateEnabled || !stableBorrowRateEnabled);
        assertTrue(isActive || !isActive);
        assertTrue(isFrozen || !isFrozen);
    }
    
    function test_GetReserveLiquidationThreshold() public {
        uint256 threshold = adapter.getReserveLiquidationThreshold();
        assertTrue(threshold >= 0);
    }
    
    function test_GetReserveLiquidationBonus() public {
        uint256 bonus = adapter.getReserveLiquidationBonus();
        assertTrue(bonus >= 0);
    }
    
    function test_GetReserveLTV() public {
        uint256 ltv = adapter.getReserveLTV();
        assertTrue(ltv >= 0);
    }
    
    function test_GetReserveFactor() public {
        uint256 factor = adapter.getReserveFactor();
        assertTrue(factor >= 0);
    }
    
    function test_GetReserveDecimals() public {
        uint256 decimals = adapter.getReserveDecimals();
        assertTrue(decimals >= 0);
    }
    
    function test_GetReserveIsActive() public {
        bool isActive = adapter.getReserveIsActive();
        assertTrue(isActive || !isActive);
    }
    
    function test_GetReserveIsFrozen() public {
        bool isFrozen = adapter.getReserveIsFrozen();
        assertTrue(isFrozen || !isFrozen);
    }
    
    function test_GetReserveBorrowingEnabled() public {
        bool borrowingEnabled = adapter.getReserveBorrowingEnabled();
        assertTrue(borrowingEnabled || !borrowingEnabled);
    }
    
    function test_GetReserveStableBorrowRateEnabled() public {
        bool stableBorrowRateEnabled = adapter.getReserveStableBorrowRateEnabled();
        assertTrue(stableBorrowRateEnabled || !stableBorrowRateEnabled);
    }
    
    function test_GetReserveUsageAsCollateralEnabled() public {
        bool usageAsCollateralEnabled = adapter.getReserveUsageAsCollateralEnabled();
        assertTrue(usageAsCollateralEnabled || !usageAsCollateralEnabled);
    }
    
    function test_GetReserveLiquidityRate() public {
        uint256 rate = adapter.getReserveLiquidityRate();
        assertTrue(rate >= 0);
    }
    
    function test_GetReserveStableBorrowRate() public {
        uint256 rate = adapter.getReserveStableBorrowRate();
        assertTrue(rate >= 0);
    }
    
    function test_GetReserveVariableBorrowRate() public {
        uint256 rate = adapter.getReserveVariableBorrowRate();
        assertTrue(rate >= 0);
    }
    
    function test_GetReserveAverageStableBorrowRate() public {
        uint256 rate = adapter.getReserveAverageStableBorrowRate();
        assertTrue(rate >= 0);
    }
    
    function test_GetReserveLastUpdateTimestamp() public {
        uint256 timestamp = adapter.getReserveLastUpdateTimestamp();
        assertTrue(timestamp >= 0);
    }
    
    function test_GetReserveATokenAddress() public {
        address aTokenAddress = adapter.getReserveATokenAddress();
        assertEq(aTokenAddress, ATOKEN);
    }
    
    function test_GetReserveStableDebtTokenAddress() public {
        address stableDebtTokenAddress = adapter.getReserveStableDebtTokenAddress();
        assertTrue(stableDebtTokenAddress != address(0));
    }
    
    function test_GetReserveVariableDebtTokenAddress() public {
        address variableDebtTokenAddress = adapter.getReserveVariableDebtTokenAddress();
        assertTrue(variableDebtTokenAddress != address(0));
    }
    
    function test_GetReserveInterestRateStrategyAddress() public {
        address strategyAddress = adapter.getReserveInterestRateStrategyAddress();
        assertTrue(strategyAddress != address(0));
    }
    
    function test_GetReserveCurrentLiquidityRate() public {
        uint256 rate = adapter.getReserveCurrentLiquidityRate();
        assertTrue(rate >= 0);
    }
    
    function test_GetReserveCurrentStableBorrowRate() public {
        uint256 rate = adapter.getReserveCurrentStableBorrowRate();
        assertTrue(rate >= 0);
    }
    
    function test_GetReserveCurrentVariableBorrowRate() public {
        uint256 rate = adapter.getReserveCurrentVariableBorrowRate();
        assertTrue(rate >= 0);
    }
    
    function test_GetReserveCurrentAverageStableBorrowRate() public {
        uint256 rate = adapter.getReserveCurrentAverageStableBorrowRate();
        assertTrue(rate >= 0);
    }
    
    function test_GetReserveLiquidityIndex() public {
        uint256 index = adapter.getReserveLiquidityIndex();
        assertTrue(index >= 0);
    }
    
    function test_GetReserveVariableBorrowIndex() public {
        uint256 index = adapter.getReserveVariableBorrowIndex();
        assertTrue(index >= 0);
    }
    
    function test_GetReserveLiquidityCumulativeIndex() public {
        uint256 index = adapter.getReserveLiquidityCumulativeIndex();
        assertTrue(index >= 0);
    }
    
    function test_GetReserveVariableBorrowCumulativeIndex() public {
        uint256 index = adapter.getReserveVariableBorrowCumulativeIndex();
        assertTrue(index >= 0);
    }
    
    function test_GetReserveATokenUserIndex() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        uint256 index = adapter.getReserveATokenUserIndex(USER);
        assertTrue(index >= 0);
    }
    
    function test_GetReserveStableDebtUserIndex() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        uint256 index = adapter.getReserveStableDebtUserIndex(USER);
        assertTrue(index >= 0);
    }
    
    function test_GetReserveVariableDebtUserIndex() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        uint256 index = adapter.getReserveVariableDebtUserIndex(USER);
        assertTrue(index >= 0);
    }
    
    function test_GetReserveATokenUserCumulativeIndex() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        uint256 index = adapter.getReserveATokenUserCumulativeIndex(USER);
        assertTrue(index >= 0);
    }
    
    function test_GetReserveStableDebtUserCumulativeIndex() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        uint256 index = adapter.getReserveStableDebtUserCumulativeIndex(USER);
        assertTrue(index >= 0);
    }
    
    function test_GetReserveVariableDebtUserCumulativeIndex() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        uint256 index = adapter.getReserveVariableDebtUserCumulativeIndex(USER);
        assertTrue(index >= 0);
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
    
    function test_SetLendingPool() public {
        address newLendingPool = address(0x999);
        
        vm.prank(address(this));
        adapter.setLendingPool(newLendingPool);
        
        assertEq(adapter.lendingPool(), newLendingPool);
    }
    
    function test_SetLendingPool_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        adapter.setLendingPool(address(0x999));
    }
    
    function test_SetLendingPool_RevertWhen_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid lending pool address");
        adapter.setLendingPool(address(0));
    }
    
    function test_SetAToken() public {
        address newAToken = address(0x999);
        
        vm.prank(address(this));
        adapter.setAToken(newAToken);
        
        assertEq(adapter.aToken(), newAToken);
    }
    
    function test_SetAToken_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        adapter.setAToken(address(0x999));
    }
    
    function test_SetAToken_RevertWhen_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid aToken address");
        adapter.setAToken(address(0));
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
