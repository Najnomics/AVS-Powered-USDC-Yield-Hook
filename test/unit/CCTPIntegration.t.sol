// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {CCTPIntegration} from "../../src/circle/CCTPIntegration.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/**
 * @title CCTPIntegrationUnitTest
 * @notice Basic unit tests for CCTPIntegration
 * @dev Tests basic functionality and constants
 */
contract CCTPIntegrationUnitTest is Test {
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    CCTPIntegration public cctpIntegration;
    MockUSDC public usdc;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant USER = address(0x1);
    address constant RECIPIENT = address(0x3);
    
    uint256 constant INITIAL_BALANCE = 100000e6; // 100k USDC
    uint256 constant TRANSFER_AMOUNT = 10000e6; // 10k USDC
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        usdc = new MockUSDC();
        
        cctpIntegration = new CCTPIntegration();
        
        // Setup initial state
        usdc.mint(USER, INITIAL_BALANCE);
        usdc.mint(address(cctpIntegration), INITIAL_BALANCE);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(cctpIntegration.USDC(), 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F);
        assertEq(cctpIntegration.owner(), address(this));
    }
    
    function test_Constructor_Constants() public {
        assertEq(cctpIntegration.MIN_TRANSFER_AMOUNT(), 1e6);
        assertEq(cctpIntegration.MAX_TRANSFER_AMOUNT(), 10_000_000e6);
        assertEq(cctpIntegration.MAX_FAST_TRANSFER_FEE(), 100);
        assertEq(cctpIntegration.STANDARD_TRANSFER_TIME(), 1200);
        assertEq(cctpIntegration.FAST_TRANSFER_TIME(), 30);
    }
    
    /*//////////////////////////////////////////////////////////////
                            PAUSE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Pause() public {
        vm.prank(address(this));
        cctpIntegration.pause();
        
        assertTrue(cctpIntegration.paused());
    }
    
    function test_Pause_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.pause();
    }
    
    function test_Unpause() public {
        vm.prank(address(this));
        cctpIntegration.pause();
        
        vm.prank(address(this));
        cctpIntegration.unpause();
        
        assertFalse(cctpIntegration.paused());
    }
    
    function test_Unpause_RevertWhen_NotOwner() public {
        vm.prank(address(this));
        cctpIntegration.pause();
        
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.unpause();
    }
    
    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EmergencyWithdraw() public {
        uint256 initialBalance = usdc.balanceOf(address(this));
        
        vm.prank(address(this));
        cctpIntegration.emergencyWithdraw(address(usdc), address(this), INITIAL_BALANCE);
        
        assertEq(usdc.balanceOf(address(this)), initialBalance + INITIAL_BALANCE);
    }
    
    function test_EmergencyWithdraw_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.emergencyWithdraw(address(usdc), address(this), INITIAL_BALANCE);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(cctpIntegration.USDC(), 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F);
        assertTrue(cctpIntegration.MIN_TRANSFER_AMOUNT() > 0);
        assertTrue(cctpIntegration.MAX_TRANSFER_AMOUNT() > 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EmergencyWithdraw_ZeroAmount() public {
        vm.prank(address(this));
        cctpIntegration.emergencyWithdraw(address(usdc), address(this), 0);
        
        // Should succeed with zero amount
        assertTrue(true);
    }
    
    function test_EmergencyWithdraw_ExceedsBalance() public {
        uint256 excessAmount = INITIAL_BALANCE + 1;
        
        vm.prank(address(this));
        vm.expectRevert();
        cctpIntegration.emergencyWithdraw(address(usdc), address(this), excessAmount);
    }
}