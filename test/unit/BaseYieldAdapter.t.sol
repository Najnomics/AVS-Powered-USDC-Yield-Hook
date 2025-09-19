// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {BaseYieldAdapter} from "../../src/protocols/BaseYieldAdapter.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestYieldAdapter
 * @notice Concrete implementation of BaseYieldAdapter for testing
 */
contract TestYieldAdapter is BaseYieldAdapter {
    constructor() BaseYieldAdapter(keccak256("TEST"), "Test Protocol") {
        minDeposit = 100e6;
        maxTvl = 1000000e6;
    }
    
    function deposit(uint256 amount) external override returns (uint256 shares) {
        _validateDeposit(amount);
        _transferUSDCFrom(msg.sender, amount);
        shares = amount;
        emit Deposited(msg.sender, amount, shares);
        return shares;
    }
    
    function withdraw(uint256 shares) external override returns (uint256 amount) {
        _validateWithdraw(shares);
        amount = shares;
        _transferUSDC(msg.sender, amount);
        emit Withdrawn(msg.sender, shares, amount);
        return amount;
    }
    
    function getCurrentYield() external view override returns (uint256 yieldRate) {
        return 500; // 5% APY
    }
    
    function getUserBalance(address user) external view override returns (uint256 shares, uint256 value) {
        shares = 0;
        value = 0;
        return (shares, value);
    }
    
    function getTotalValueLocked() external view override returns (uint256 tvl) {
        return 0; // Start with 0 TVL to allow deposits
    }
    
    function getUtilization() external view override returns (uint256 utilization) {
        return 5000; // 50%
    }
    
    function getRiskScore() external view override returns (uint256 riskScore) {
        return 1000; // 10%
    }
    
    function canDeposit(uint256 amount) external view override returns (bool canDeposit_, uint256 maxDepositAmount) {
        canDeposit_ = amount >= minDeposit && amount <= maxTvl;
        maxDepositAmount = maxTvl;
        return (canDeposit_, maxDepositAmount);
    }
    
    function canWithdraw(uint256 shares) external view override returns (bool canWithdraw_, uint256 availableShares) {
        canWithdraw_ = true;
        availableShares = shares;
        return (canWithdraw_, availableShares);
    }
    
    function calculateShares(uint256 amount) external view override returns (uint256 shares) {
        return amount;
    }
    
    function calculateAmount(uint256 shares) external view override returns (uint256 amount) {
        return shares;
    }
}

/**
 * @title BaseYieldAdapterUnitTest
 * @notice Comprehensive unit tests for BaseYieldAdapter
 * @dev Tests all functions, edge cases, and error conditions
 */
contract BaseYieldAdapterUnitTest is Test {
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    TestYieldAdapter public adapter;
    MockUSDC public usdc;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant USER = address(0x1);
    address constant TREASURY = address(0x2);
    
    uint256 constant INITIAL_BALANCE = 100000e6; // 100k USDC
    uint256 constant DEPOSIT_AMOUNT = 10000e6; // 10k USDC
    uint256 constant WITHDRAWAL_AMOUNT = 5000e6; // 5k USDC
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        usdc = new MockUSDC();
        
        // Deploy MockUSDC at the hardcoded address that BaseYieldAdapter expects
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        vm.etch(usdcAddress, address(usdc).code);
        
        // Create a concrete implementation for testing
        adapter = new TestYieldAdapter();
        
        // Setup initial state
        usdc.mint(USER, INITIAL_BALANCE);
        usdc.mint(address(adapter), INITIAL_BALANCE);
        
        // Mint USDC to user on the hardcoded USDC address
        MockUSDC(usdcAddress).mint(USER, INITIAL_BALANCE);
        MockUSDC(usdcAddress).mint(address(adapter), INITIAL_BALANCE);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(adapter.USDC(), 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F);
        assertEq(adapter.protocolId(), keccak256("TEST"));
        assertEq(adapter.protocolName(), "Test Protocol");
        assertTrue(adapter.isActive());
    }
    
    function test_Constructor_Constants() public {
        assertEq(adapter.minDeposit(), 100e6);
        assertEq(adapter.maxTvl(), 1000000e6);
    }
    
    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Deposit() public {
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        
        vm.prank(USER);
        IERC20(usdcAddress).approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        uint256 shares = adapter.deposit(DEPOSIT_AMOUNT);
        
        assertEq(shares, DEPOSIT_AMOUNT);
    }
    
    function test_Deposit_RevertWhen_InsufficientAllowance() public {
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        
        vm.prank(USER);
        IERC20(usdcAddress).approve(address(adapter), DEPOSIT_AMOUNT - 1);
        
        vm.prank(USER);
        vm.expectRevert();
        adapter.deposit(DEPOSIT_AMOUNT);
    }
    
    function test_Deposit_RevertWhen_AmountTooSmall() public {
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        uint256 smallAmount = adapter.minDeposit() - 1;
        
        vm.prank(USER);
        IERC20(usdcAddress).approve(address(adapter), smallAmount);
        
        vm.prank(USER);
        vm.expectRevert("Amount below minimum");
        adapter.deposit(smallAmount);
    }
    
    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Withdraw() public {
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        
        // First deposit
        vm.prank(USER);
        IERC20(usdcAddress).approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // Then withdraw
        vm.prank(USER);
        uint256 amount = adapter.withdraw(WITHDRAWAL_AMOUNT);
        
        assertEq(amount, WITHDRAWAL_AMOUNT);
    }
    
    function test_Withdraw_RevertWhen_ZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert("Invalid shares");
        adapter.withdraw(0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            YIELD TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetCurrentYield() public {
        uint256 yield = adapter.getCurrentYield();
        assertEq(yield, 500); // 5% APY
    }
    
    function test_GetUserBalance() public {
        (uint256 shares, uint256 value) = adapter.getUserBalance(USER);
        
        assertEq(shares, 0);
        assertEq(value, 0);
    }
    
    function test_GetTotalValueLocked() public {
        uint256 tvl = adapter.getTotalValueLocked();
        assertEq(tvl, 0);
    }
    
    function test_GetUtilization() public {
        uint256 utilization = adapter.getUtilization();
        assertEq(utilization, 5000); // 50%
    }
    
    function test_GetRiskScore() public {
        uint256 riskScore = adapter.getRiskScore();
        assertEq(riskScore, 1000); // 10%
    }
    
    /*//////////////////////////////////////////////////////////////
                            VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CanDeposit() public {
        (bool canDeposit, uint256 maxDeposit) = adapter.canDeposit(DEPOSIT_AMOUNT);
        
        assertTrue(canDeposit);
        assertEq(maxDeposit, 1000000e6);
    }
    
    function test_CanDeposit_RevertWhen_AmountTooSmall() public {
        uint256 smallAmount = adapter.minDeposit() - 1;
        
        (bool canDeposit, uint256 maxDeposit) = adapter.canDeposit(smallAmount);
        
        assertFalse(canDeposit);
        assertEq(maxDeposit, 1000000e6);
    }
    
    function test_CanWithdraw() public {
        (bool canWithdraw, uint256 availableShares) = adapter.canWithdraw(WITHDRAWAL_AMOUNT);
        
        assertTrue(canWithdraw);
        assertEq(availableShares, WITHDRAWAL_AMOUNT);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CalculateShares() public {
        uint256 shares = adapter.calculateShares(DEPOSIT_AMOUNT);
        assertEq(shares, DEPOSIT_AMOUNT);
    }
    
    function test_CalculateAmount() public {
        uint256 amount = adapter.calculateAmount(DEPOSIT_AMOUNT);
        assertEq(amount, DEPOSIT_AMOUNT);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(adapter.USDC(), 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F);
        assertEq(adapter.protocolId(), keccak256("TEST"));
        assertEq(adapter.protocolName(), "Test Protocol");
        assertTrue(adapter.isActive());
        assertEq(adapter.minDeposit(), 100e6);
        assertEq(adapter.maxTvl(), 1000000e6);
    }
}