// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {AaveV3Adapter} from "../../src/protocols/AaveV3Adapter.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {MockAUSDC} from "../mocks/MockAUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    MockAUSDC public ausdc;
    
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
        
        // Deploy MockAUSDC at the hardcoded address that AaveV3Adapter expects
        ausdc = new MockAUSDC();
        address ausdcAddress = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
        vm.etch(ausdcAddress, address(ausdc).code);
        
        // Deploy MockUSDC at the hardcoded address that BaseYieldAdapter expects
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        vm.etch(usdcAddress, address(usdc).code);
        
        // Deploy adapter
        adapter = new AaveV3Adapter();
        
        // Setup initial state
        usdc.mint(USER, INITIAL_BALANCE);
        usdc.mint(address(adapter), INITIAL_BALANCE);
        
        // Mint USDC to user on the hardcoded USDC address
        MockUSDC(usdcAddress).mint(USER, INITIAL_BALANCE);
        // Don't mint to adapter to avoid TVL issues
        
        // Give user allowance to adapter on the hardcoded USDC address
        vm.prank(USER);
        IERC20(usdcAddress).approve(address(adapter), INITIAL_BALANCE);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(adapter.USDC(), 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F);
        assertEq(adapter.protocolId(), keccak256("AAVE_V3"));
        assertEq(adapter.protocolName(), "Aave V3 USDC");
        assertTrue(adapter.isActive());
    }
    
    function test_Constructor_Constants() public {
        assertEq(adapter.AAVE_POOL(), 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
        assertEq(adapter.AUSDC(), 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        assertEq(adapter.minDeposit(), 100e6);
        assertEq(adapter.maxTvl(), 100_000_000e6);
    }
    
    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Deposit() public {
        uint256 initialShares = adapter.userShares(USER);
        
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        uint256 shares = adapter.deposit(DEPOSIT_AMOUNT);
        
        assertEq(shares, DEPOSIT_AMOUNT);
        assertEq(adapter.userShares(USER), initialShares + DEPOSIT_AMOUNT);
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
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // Then withdraw
        vm.prank(USER);
        uint256 amount = adapter.withdraw(WITHDRAWAL_AMOUNT);
        
        assertEq(amount, WITHDRAWAL_AMOUNT);
        assertEq(adapter.userShares(USER), DEPOSIT_AMOUNT - WITHDRAWAL_AMOUNT);
    }
    
    function test_Withdraw_RevertWhen_InsufficientShares() public {
        vm.prank(USER);
        vm.expectRevert("Insufficient shares");
        adapter.withdraw(WITHDRAWAL_AMOUNT);
    }
    
    /*//////////////////////////////////////////////////////////////
                            YIELD TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetCurrentYield() public {
        uint256 yield = adapter.getCurrentYield();
        assertEq(yield, 450); // 4.5% APY placeholder
    }
    
    function test_GetUserBalance() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        (uint256 shares, uint256 value) = adapter.getUserBalance(USER);
        
        assertEq(shares, DEPOSIT_AMOUNT);
        assertEq(value, DEPOSIT_AMOUNT);
    }
    
    function test_GetTotalValueLocked() public {
        uint256 tvl = adapter.getTotalValueLocked();
        assertEq(tvl, 50_000_000e6); // 50M USDC placeholder
    }
    
    function test_GetUtilization() public {
        uint256 utilization = adapter.getUtilization();
        assertEq(utilization, 7500); // 75% utilization placeholder
    }
    
    function test_GetRiskScore() public {
        uint256 riskScore = adapter.getRiskScore();
        assertEq(riskScore, 1500); // 15% risk score placeholder
    }
    
    /*//////////////////////////////////////////////////////////////
                            VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CanDeposit() public {
        (bool canDeposit, uint256 maxDeposit) = adapter.canDeposit(DEPOSIT_AMOUNT);
        
        assertTrue(canDeposit);
        assertTrue(maxDeposit > 0);
    }
    
    function test_CanDeposit_RevertWhen_AmountTooSmall() public {
        uint256 smallAmount = adapter.minDeposit() - 1;
        
        (bool canDeposit, uint256 maxDeposit) = adapter.canDeposit(smallAmount);
        
        assertFalse(canDeposit);
        assertTrue(maxDeposit > 0); // maxDeposit should be available, but amount is too small
    }
    
    function test_CanWithdraw() public {
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        
        // First deposit
        vm.prank(USER);
        IERC20(usdcAddress).approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // Call canWithdraw from USER's context
        vm.prank(USER);
        (bool canWithdraw, uint256 availableShares) = adapter.canWithdraw(WITHDRAWAL_AMOUNT);
        
        assertTrue(canWithdraw);
        assertEq(availableShares, DEPOSIT_AMOUNT);
    }
    
    function test_CanWithdraw_RevertWhen_NoShares() public {
        (bool canWithdraw, uint256 availableShares) = adapter.canWithdraw(WITHDRAWAL_AMOUNT);
        
        assertFalse(canWithdraw);
        assertEq(availableShares, 0);
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
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Deposit_MaxAmount() public {
        address usdcAddress = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
        uint256 currentTvl = adapter.getTotalValueLocked();
        uint256 maxAmount = adapter.maxTvl() - currentTvl; // Deposit up to the limit
        
        // Mint enough USDC to user
        MockUSDC(usdcAddress).mint(USER, maxAmount);
        
        vm.prank(USER);
        IERC20(usdcAddress).approve(address(adapter), maxAmount);
        
        vm.prank(USER);
        uint256 shares = adapter.deposit(maxAmount);
        
        assertEq(shares, maxAmount);
        assertEq(adapter.userShares(USER), maxAmount);
    }
    
    function test_Withdraw_AllShares() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(adapter), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        adapter.deposit(DEPOSIT_AMOUNT);
        
        // Withdraw all
        vm.prank(USER);
        uint256 amount = adapter.withdraw(DEPOSIT_AMOUNT);
        
        assertEq(amount, DEPOSIT_AMOUNT);
        assertEq(adapter.userShares(USER), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(adapter.USDC(), 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F);
        assertEq(adapter.protocolId(), keccak256("AAVE_V3"));
        assertEq(adapter.protocolName(), "Aave V3 USDC");
        assertTrue(adapter.isActive());
        assertEq(adapter.minDeposit(), 100e6);
        assertEq(adapter.maxTvl(), 100_000_000e6);
    }
}