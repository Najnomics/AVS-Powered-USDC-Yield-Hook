// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {CCTPIntegration} from "../../src/circle/CCTPIntegration.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/**
 * @title CCTPIntegrationUnitTest
 * @notice Comprehensive unit tests for CCTPIntegration
 * @dev Tests all functions, edge cases, and error conditions
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
    address constant TREASURY = address(0x2);
    address constant RECIPIENT = address(0x3);
    
    uint256 constant INITIAL_BALANCE = 100000e6; // 100k USDC
    uint256 constant TRANSFER_AMOUNT = 10000e6; // 10k USDC
    
    uint32 constant ETHEREUM_DOMAIN = 0;
    uint32 constant POLYGON_DOMAIN = 137;
    uint32 constant ARBITRUM_DOMAIN = 42161;
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        usdc = new MockUSDC();
        
        cctpIntegration = new CCTPIntegration(
            address(usdc),
            TREASURY
        );
        
        // Setup initial state
        usdc.mint(USER, INITIAL_BALANCE);
        usdc.mint(address(cctpIntegration), INITIAL_BALANCE);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(cctpIntegration.USDC(), address(usdc));
        assertEq(cctpIntegration.treasury(), TREASURY);
        assertEq(cctpIntegration.owner(), address(this));
    }
    
    function test_Constructor_RevertWhen_ZeroUSDC() public {
        vm.expectRevert("Invalid USDC address");
        new CCTPIntegration(
            address(0),
            TREASURY
        );
    }
    
    function test_Constructor_RevertWhen_ZeroTreasury() public {
        vm.expectRevert("Invalid treasury address");
        new CCTPIntegration(
            address(usdc),
            address(0)
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_TransferUSDC() public {
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            destinationDomain: POLYGON_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), TRANSFER_AMOUNT);
        
        vm.prank(USER);
        (bool success, bytes32 messageHash) = cctpIntegration.transferUSDC(params);
        
        assertTrue(success);
        assertTrue(messageHash != bytes32(0));
    }
    
    function test_TransferUSDC_RevertWhen_InsufficientAllowance() public {
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            destinationDomain: POLYGON_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), TRANSFER_AMOUNT - 1);
        
        vm.prank(USER);
        vm.expectRevert("ERC20: insufficient allowance");
        cctpIntegration.transferUSDC(params);
    }
    
    function test_TransferUSDC_RevertWhen_ZeroAmount() public {
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: 0,
            destinationDomain: POLYGON_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        vm.expectRevert("Invalid transfer amount");
        cctpIntegration.transferUSDC(params);
    }
    
    function test_TransferUSDC_RevertWhen_ExceedsMaxAmount() public {
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: cctpIntegration.MAX_TRANSFER_AMOUNT() + 1,
            destinationDomain: POLYGON_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), cctpIntegration.MAX_TRANSFER_AMOUNT() + 1);
        
        vm.prank(USER);
        vm.expectRevert("Amount exceeds maximum");
        cctpIntegration.transferUSDC(params);
    }
    
    function test_TransferUSDC_RevertWhen_InvalidDomain() public {
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            destinationDomain: 999999, // invalid domain
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), TRANSFER_AMOUNT);
        
        vm.prank(USER);
        vm.expectRevert("Unsupported destination domain");
        cctpIntegration.transferUSDC(params);
    }
    
    function test_TransferUSDC_RevertWhen_SameDomain() public {
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            destinationDomain: ETHEREUM_DOMAIN, // same as source
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), TRANSFER_AMOUNT);
        
        vm.prank(USER);
        vm.expectRevert("Same domain transfer");
        cctpIntegration.transferUSDC(params);
    }
    
    /*//////////////////////////////////////////////////////////////
                            RECEIVE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ReceiveUSDC() public {
        CCTPIntegration.TransferStatus memory status = CCTPIntegration.TransferStatus({
            messageHash: keccak256("test_message"),
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            status: "completed",
            completedTimestamp: block.timestamp,
            failureReason: ""
        });
        
        vm.prank(USER);
        cctpIntegration.receiveUSDC(status);
        
        assertEq(usdc.balanceOf(RECIPIENT), TRANSFER_AMOUNT);
    }
    
    function test_ReceiveUSDC_RevertWhen_InvalidStatus() public {
        CCTPIntegration.TransferStatus memory status = CCTPIntegration.TransferStatus({
            messageHash: bytes32(0), // invalid
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            status: "completed",
            completedTimestamp: block.timestamp,
            failureReason: ""
        });
        
        vm.prank(USER);
        vm.expectRevert("Invalid transfer status");
        cctpIntegration.receiveUSDC(status);
    }
    
    function test_ReceiveUSDC_RevertWhen_ZeroAmount() public {
        CCTPIntegration.TransferStatus memory status = CCTPIntegration.TransferStatus({
            messageHash: keccak256("test_message"),
            recipient: RECIPIENT,
            amount: 0,
            status: "completed",
            completedTimestamp: block.timestamp,
            failureReason: ""
        });
        
        vm.prank(USER);
        vm.expectRevert("Invalid transfer amount");
        cctpIntegration.receiveUSDC(status);
    }
    
    /*//////////////////////////////////////////////////////////////
                            FAST TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ExecuteFastTransfer() public {
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            destinationDomain: POLYGON_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), TRANSFER_AMOUNT);
        
        vm.prank(USER);
        (bool success, bytes32 messageHash) = cctpIntegration.executeFastTransfer(params);
        
        assertTrue(success);
        assertTrue(messageHash != bytes32(0));
    }
    
    function test_ExecuteFastTransfer_RevertWhen_NotAvailable() public {
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            destinationDomain: 999999, // unsupported domain
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), TRANSFER_AMOUNT);
        
        vm.prank(USER);
        vm.expectRevert("Fast transfer not available");
        cctpIntegration.executeFastTransfer(params);
    }
    
    /*//////////////////////////////////////////////////////////////
                            FEE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetTransferFee() public {
        uint256 fee = cctpIntegration.getTransferFee(TRANSFER_AMOUNT, POLYGON_DOMAIN);
        assertTrue(fee > 0);
    }
    
    function test_GetTransferFee_RevertWhen_InvalidDomain() public {
        vm.expectRevert("Unsupported destination domain");
        cctpIntegration.getTransferFee(TRANSFER_AMOUNT, 999999);
    }
    
    function test_GetFastTransferFee() public {
        uint256 fee = cctpIntegration.getFastTransferFee(TRANSFER_AMOUNT, POLYGON_DOMAIN);
        assertTrue(fee >= 0);
    }
    
    function test_IsFastTransferAvailable() public {
        assertTrue(cctpIntegration.isFastTransferAvailable(ETHEREUM_DOMAIN, POLYGON_DOMAIN));
        assertFalse(cctpIntegration.isFastTransferAvailable(ETHEREUM_DOMAIN, 999999));
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATUS QUERY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetTransferStatus() public {
        bytes32 messageHash = keccak256("test_message");
        
        (
            string memory status,
            uint256 completedTimestamp,
            string memory failureReason
        ) = cctpIntegration.getTransferStatus(messageHash);
        
        assertEq(status, "pending");
        assertEq(completedTimestamp, 0);
        assertEq(failureReason, "");
    }
    
    function test_IsTransferCompleted() public {
        bytes32 messageHash = keccak256("test_message");
        assertFalse(cctpIntegration.isTransferCompleted(messageHash));
    }
    
    /*//////////////////////////////////////////////////////////////
                            OPTIMIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_OptimizeTransfer() public {
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            destinationDomain: POLYGON_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), TRANSFER_AMOUNT);
        
        vm.prank(USER);
        (bool success, bytes32 messageHash) = cctpIntegration.optimizeTransfer(
            params,
            "" // empty optimization data
        );
        
        assertTrue(success);
        assertTrue(messageHash != bytes32(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                            BATCH OPERATIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BatchTransfer() public {
        CCTPIntegration.TransferParams[] memory params = new CCTPIntegration.TransferParams[](2);
        
        params[0] = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            destinationDomain: POLYGON_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        params[1] = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: TRANSFER_AMOUNT,
            destinationDomain: ARBITRUM_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), TRANSFER_AMOUNT * 2);
        
        vm.prank(USER);
        (bool[] memory successes, bytes32[] memory messageHashes) = cctpIntegration.batchTransfer(params);
        
        assertTrue(successes[0]);
        assertTrue(successes[1]);
        assertTrue(messageHashes[0] != bytes32(0));
        assertTrue(messageHashes[1] != bytes32(0));
    }
    
    function test_BatchTransfer_RevertWhen_EmptyArray() public {
        CCTPIntegration.TransferParams[] memory params = new CCTPIntegration.TransferParams[](0);
        
        vm.prank(USER);
        vm.expectRevert("Empty batch");
        cctpIntegration.batchTransfer(params);
    }
    
    function test_BatchTransfer_RevertWhen_TooManyTransfers() public {
        CCTPIntegration.TransferParams[] memory params = new CCTPIntegration.TransferParams[](101); // > 100
        
        for (uint256 i = 0; i < 101; i++) {
            params[i] = CCTPIntegration.TransferParams({
                sender: USER,
                recipient: RECIPIENT,
                amount: TRANSFER_AMOUNT,
                destinationDomain: POLYGON_DOMAIN,
                recipientAddress: RECIPIENT
            });
        }
        
        vm.prank(USER);
        vm.expectRevert("Too many transfers");
        cctpIntegration.batchTransfer(params);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetTreasury() public {
        address newTreasury = address(0x999);
        
        vm.prank(address(this));
        cctpIntegration.setTreasury(newTreasury);
        
        assertEq(cctpIntegration.treasury(), newTreasury);
    }
    
    function test_SetTreasury_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.setTreasury(address(0x999));
    }
    
    function test_SetTreasury_RevertWhen_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid treasury address");
        cctpIntegration.setTreasury(address(0));
    }
    
    function test_SetMaxTransferAmount() public {
        uint256 newMax = 20000000e6; // 20M USDC
        
        vm.prank(address(this));
        cctpIntegration.setMaxTransferAmount(newMax);
        
        assertEq(cctpIntegration.MAX_TRANSFER_AMOUNT(), newMax);
    }
    
    function test_SetMaxTransferAmount_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.setMaxTransferAmount(20000000e6);
    }
    
    function test_SetTransferFee() public {
        uint256 newFee = 100; // 1%
        
        vm.prank(address(this));
        cctpIntegration.setTransferFee(newFee);
        
        assertEq(cctpIntegration.transferFee(), newFee);
    }
    
    function test_SetTransferFee_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.setTransferFee(100);
    }
    
    function test_SetTransferFee_RevertWhen_InvalidFee() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid transfer fee");
        cctpIntegration.setTransferFee(10001); // > 100%
    }
    
    function test_AddSupportedDomain() public {
        uint32 newDomain = 10; // Optimism
        
        vm.prank(address(this));
        cctpIntegration.addSupportedDomain(newDomain);
        
        assertTrue(cctpIntegration.isDomainSupported(newDomain));
    }
    
    function test_AddSupportedDomain_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.addSupportedDomain(10);
    }
    
    function test_RemoveSupportedDomain() public {
        vm.prank(address(this));
        cctpIntegration.removeSupportedDomain(POLYGON_DOMAIN);
        
        assertFalse(cctpIntegration.isDomainSupported(POLYGON_DOMAIN));
    }
    
    function test_RemoveSupportedDomain_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.removeSupportedDomain(POLYGON_DOMAIN);
    }
    
    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EmergencyWithdraw() public {
        uint256 initialBalance = usdc.balanceOf(TREASURY);
        
        vm.prank(address(this));
        cctpIntegration.emergencyWithdraw();
        
        assertEq(usdc.balanceOf(TREASURY), initialBalance + INITIAL_BALANCE);
        assertEq(usdc.balanceOf(address(cctpIntegration)), 0);
    }
    
    function test_EmergencyWithdraw_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.emergencyWithdraw();
    }
    
    function test_EmergencyWithdrawToken() public {
        address token = address(usdc);
        uint256 amount = 1000e6;
        
        usdc.mint(address(cctpIntegration), amount);
        
        vm.prank(address(this));
        cctpIntegration.emergencyWithdrawToken(token, amount);
        
        assertEq(usdc.balanceOf(TREASURY), amount);
    }
    
    function test_EmergencyWithdrawToken_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cctpIntegration.emergencyWithdrawToken(address(usdc), 1000e6);
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetSupportedDomains() public {
        uint32[] memory domains = cctpIntegration.getSupportedDomains();
        assertTrue(domains.length > 0);
    }
    
    function test_IsDomainSupported() public {
        assertTrue(cctpIntegration.isDomainSupported(ETHEREUM_DOMAIN));
        assertTrue(cctpIntegration.isDomainSupported(POLYGON_DOMAIN));
        assertTrue(cctpIntegration.isDomainSupported(ARBITRUM_DOMAIN));
        assertFalse(cctpIntegration.isDomainSupported(999999));
    }
    
    function test_GetTransferLimits() public {
        (uint256 minAmount, uint256 maxAmount) = cctpIntegration.getTransferLimits(
            ETHEREUM_DOMAIN,
            POLYGON_DOMAIN
        );
        
        assertTrue(minAmount > 0);
        assertTrue(maxAmount > minAmount);
    }
    
    function test_CheckTransferAllowance() public {
        bool allowed = cctpIntegration.checkTransferAllowance(USER, TRANSFER_AMOUNT);
        assertTrue(allowed);
    }
    
    function test_GetDailyVolume() public {
        uint256 volume = cctpIntegration.getDailyVolume(USER);
        assertEq(volume, 0); // No transfers yet
    }
    
    function test_GetTotalVolume() public {
        uint256 volume = cctpIntegration.getTotalVolume();
        assertEq(volume, 0); // No transfers yet
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(cctpIntegration.USDC(), address(usdc));
        assertTrue(cctpIntegration.MIN_TRANSFER_AMOUNT() > 0);
        assertTrue(cctpIntegration.MAX_TRANSFER_AMOUNT() > 0);
        assertTrue(cctpIntegration.transferFee() >= 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_TransferUSDC_MinAmount() public {
        uint256 minAmount = cctpIntegration.MIN_TRANSFER_AMOUNT();
        
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: minAmount,
            destinationDomain: POLYGON_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), minAmount);
        
        vm.prank(USER);
        (bool success, bytes32 messageHash) = cctpIntegration.transferUSDC(params);
        
        assertTrue(success);
        assertTrue(messageHash != bytes32(0));
    }
    
    function test_TransferUSDC_MaxAmount() public {
        uint256 maxAmount = cctpIntegration.MAX_TRANSFER_AMOUNT();
        
        CCTPIntegration.TransferParams memory params = CCTPIntegration.TransferParams({
            sender: USER,
            recipient: RECIPIENT,
            amount: maxAmount,
            destinationDomain: POLYGON_DOMAIN,
            recipientAddress: RECIPIENT
        });
        
        vm.prank(USER);
        usdc.approve(address(cctpIntegration), maxAmount);
        
        vm.prank(USER);
        (bool success, bytes32 messageHash) = cctpIntegration.transferUSDC(params);
        
        assertTrue(success);
        assertTrue(messageHash != bytes32(0));
    }
    
    function test_GetTransferFee_ZeroAmount() public {
        uint256 fee = cctpIntegration.getTransferFee(0, POLYGON_DOMAIN);
        assertEq(fee, 0);
    }
    
    function test_IsFastTransferAvailable_SameDomain() public {
        assertFalse(cctpIntegration.isFastTransferAvailable(ETHEREUM_DOMAIN, ETHEREUM_DOMAIN));
    }
}
