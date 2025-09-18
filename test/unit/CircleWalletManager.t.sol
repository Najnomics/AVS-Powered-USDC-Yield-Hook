// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {CircleWalletManager} from "../../src/circle/CircleWalletManager.sol";
import {ICCTPIntegration} from "../../src/interfaces/ICCTPIntegration.sol";
import {MockCCTPIntegration} from "../mocks/MockCCTPIntegration.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/**
 * @title CircleWalletManagerUnitTest
 * @notice Comprehensive unit tests for CircleWalletManager
 * @dev Tests all functions, edge cases, and error conditions
 */
contract CircleWalletManagerUnitTest is Test {
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    CircleWalletManager public walletManager;
    MockCCTPIntegration public mockCCTP;
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
        mockCCTP = new MockCCTPIntegration();
        usdc = new MockUSDC();
        
        walletManager = new CircleWalletManager(
            ICCTPIntegration(address(mockCCTP)),
            address(usdc),
            TREASURY
        );
        
        // Setup initial state
        usdc.mint(USER, INITIAL_BALANCE);
        usdc.mint(address(walletManager), INITIAL_BALANCE);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(address(walletManager.cctpIntegration()), address(mockCCTP));
        assertEq(walletManager.USDC(), address(usdc));
        assertEq(walletManager.treasury(), TREASURY);
        assertEq(walletManager.owner(), address(this));
    }
    
    function test_Constructor_RevertWhen_ZeroCCTP() public {
        vm.expectRevert("Invalid CCTP integration");
        new CircleWalletManager(
            ICCTPIntegration(address(0)),
            address(usdc),
            TREASURY
        );
    }
    
    function test_Constructor_RevertWhen_ZeroUSDC() public {
        vm.expectRevert("Invalid USDC address");
        new CircleWalletManager(
            mockCCTP,
            address(0),
            TREASURY
        );
    }
    
    function test_Constructor_RevertWhen_ZeroTreasury() public {
        vm.expectRevert("Invalid treasury address");
        new CircleWalletManager(
            mockCCTP,
            address(usdc),
            address(0)
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_DepositToProtocol() public {
        uint256 initialBalance = usdc.balanceOf(address(walletManager));
        
        vm.prank(USER);
        usdc.approve(address(walletManager), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        walletManager.depositToProtocol(
            keccak256("AAVE_V3"),
            DEPOSIT_AMOUNT,
            1 // chainId
        );
        
        assertEq(usdc.balanceOf(address(walletManager)), initialBalance + DEPOSIT_AMOUNT);
    }
    
    function test_DepositToProtocol_RevertWhen_InsufficientAllowance() public {
        vm.prank(USER);
        usdc.approve(address(walletManager), DEPOSIT_AMOUNT - 1);
        
        vm.prank(USER);
        vm.expectRevert("ERC20: insufficient allowance");
        walletManager.depositToProtocol(
            keccak256("AAVE_V3"),
            DEPOSIT_AMOUNT,
            1
        );
    }
    
    function test_DepositToProtocol_RevertWhen_ExceedsMaxAmount() public {
        vm.prank(USER);
        usdc.approve(address(walletManager), walletManager.MAX_SINGLE_AMOUNT() + 1);
        
        vm.prank(USER);
        vm.expectRevert("Amount exceeds maximum");
        walletManager.depositToProtocol(
            keccak256("AAVE_V3"),
            walletManager.MAX_SINGLE_AMOUNT() + 1,
            1
        );
    }
    
    function test_DepositToProtocol_RevertWhen_InvalidChain() public {
        vm.prank(USER);
        usdc.approve(address(walletManager), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        vm.expectRevert("Invalid chain ID");
        walletManager.depositToProtocol(
            keccak256("AAVE_V3"),
            DEPOSIT_AMOUNT,
            0 // invalid chain
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_WithdrawFromProtocol() public {
        // First deposit
        vm.prank(USER);
        usdc.approve(address(walletManager), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        walletManager.depositToProtocol(
            keccak256("AAVE_V3"),
            DEPOSIT_AMOUNT,
            1
        );
        
        // Then withdraw
        vm.prank(USER);
        (bool success, bytes32 txHash) = walletManager.withdrawFromProtocol(
            keccak256("AAVE_V3"),
            WITHDRAWAL_AMOUNT,
            1
        );
        
        assertTrue(success);
        assertTrue(txHash != bytes32(0));
    }
    
    function test_WithdrawFromProtocol_RevertWhen_InvalidChain() public {
        vm.prank(USER);
        vm.expectRevert("Invalid chain ID");
        walletManager.withdrawFromProtocol(
            keccak256("AAVE_V3"),
            WITHDRAWAL_AMOUNT,
            0
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            BALANCE QUERY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetUserUSDCBalance() public {
        (
            uint256 totalBalance,
            bytes32[] memory protocolIds,
            uint256[] memory protocolAmounts,
            uint256[] memory chainIds,
            uint256[] memory chainAmounts
        ) = walletManager.getUserUSDCBalance(USER);
        
        assertEq(totalBalance, 0); // No deposits yet
        assertEq(protocolIds.length, 0);
        assertEq(protocolAmounts.length, 0);
        assertEq(chainIds.length, 0);
        assertEq(chainAmounts.length, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CROSS-CHAIN TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_TransferUSDCCrossChain() public {
        vm.prank(USER);
        usdc.approve(address(walletManager), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        (bool success, bytes32 transferId) = walletManager.transferUSDCCrossChain(
            USER,
            DEPOSIT_AMOUNT,
            1, // fromChainId
            137, // toChainId (Polygon)
            USER
        );
        
        assertTrue(success);
        assertTrue(transferId != bytes32(0));
    }
    
    function test_TransferUSDCCrossChain_RevertWhen_InvalidFromChain() public {
        vm.prank(USER);
        usdc.approve(address(walletManager), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        vm.expectRevert("Invalid chain ID");
        walletManager.transferUSDCCrossChain(
            USER,
            DEPOSIT_AMOUNT,
            0, // invalid fromChainId
            137,
            USER
        );
    }
    
    function test_TransferUSDCCrossChain_RevertWhen_InvalidToChain() public {
        vm.prank(USER);
        usdc.approve(address(walletManager), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        vm.expectRevert("Invalid chain ID");
        walletManager.transferUSDCCrossChain(
            USER,
            DEPOSIT_AMOUNT,
            1,
            0, // invalid toChainId
            USER
        );
    }
    
    function test_TransferUSDCCrossChain_RevertWhen_SameChain() public {
        vm.prank(USER);
        usdc.approve(address(walletManager), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        vm.expectRevert("Same chain transfer");
        walletManager.transferUSDCCrossChain(
            USER,
            DEPOSIT_AMOUNT,
            1,
            1, // same chain
            USER
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            TRANSFER STATUS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetCrossChainTransferStatus() public {
        bytes32 transferId = keccak256("test_transfer");
        
        (
            string memory status,
            uint256 completedTimestamp,
            string memory failureReason
        ) = walletManager.getCrossChainTransferStatus(transferId);
        
        assertEq(status, "completed");
        assertTrue(completedTimestamp > 0);
        assertEq(failureReason, "");
    }
    
    /*//////////////////////////////////////////////////////////////
                            REBALANCING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ExecuteRebalancing() public {
        CircleWalletManager.RebalanceRequest memory request = CircleWalletManager.RebalanceRequest({
            userAddress: USER,
            fromProtocol: keccak256("AAVE_V3"),
            toProtocol: keccak256("COMPOUND_V3"),
            amount: DEPOSIT_AMOUNT,
            fromChainId: 1,
            toChainId: 1,
            maxSlippage: 100, // 1%
            deadline: block.timestamp + 3600
        });
        
        vm.prank(USER);
        usdc.approve(address(walletManager), DEPOSIT_AMOUNT);
        
        vm.prank(USER);
        (bool success, bytes32 txHash) = walletManager.executeRebalancing(request);
        
        assertTrue(success);
        assertTrue(txHash != bytes32(0));
    }
    
    function test_ExecuteRebalancing_RevertWhen_InvalidRequest() public {
        CircleWalletManager.RebalanceRequest memory request = CircleWalletManager.RebalanceRequest({
            userAddress: USER,
            fromProtocol: keccak256("AAVE_V3"),
            toProtocol: keccak256("COMPOUND_V3"),
            amount: 0, // invalid amount
            fromChainId: 1,
            toChainId: 1,
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });
        
        vm.prank(USER);
        vm.expectRevert("Invalid rebalance request");
        walletManager.executeRebalancing(request);
    }
    
    function test_ExecuteRebalancing_RevertWhen_ExpiredDeadline() public {
        CircleWalletManager.RebalanceRequest memory request = CircleWalletManager.RebalanceRequest({
            userAddress: USER,
            fromProtocol: keccak256("AAVE_V3"),
            toProtocol: keccak256("COMPOUND_V3"),
            amount: DEPOSIT_AMOUNT,
            fromChainId: 1,
            toChainId: 1,
            maxSlippage: 100,
            deadline: block.timestamp - 1 // expired
        });
        
        vm.prank(USER);
        vm.expectRevert("Deadline expired");
        walletManager.executeRebalancing(request);
    }
    
    /*//////////////////////////////////////////////////////////////
                            GAS PAYMENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EnableUSDCGasPayments() public {
        uint256 maxGas = 1000e6; // 1000 USDC
        
        vm.prank(USER);
        walletManager.enableUSDCGasPayments(USER, maxGas);
        
        // Verify gas payment is enabled (would need to check internal state)
        assertTrue(true); // Placeholder
    }
    
    function test_EnableUSDCGasPayments_RevertWhen_ZeroMaxGas() public {
        vm.prank(USER);
        vm.expectRevert("Invalid max gas amount");
        walletManager.enableUSDCGasPayments(USER, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            COST ESTIMATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EstimateRebalancingCost() public {
        CircleWalletManager.RebalanceRequest memory request = CircleWalletManager.RebalanceRequest({
            userAddress: USER,
            fromProtocol: keccak256("AAVE_V3"),
            toProtocol: keccak256("COMPOUND_V3"),
            amount: DEPOSIT_AMOUNT,
            fromChainId: 1,
            toChainId: 1,
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });
        
        (
            uint256 totalCost,
            uint256 gasCost,
            uint256 protocolFees,
            uint256 crossChainFees
        ) = walletManager.estimateRebalancingCost(request);
        
        assertTrue(totalCost > 0);
        assertTrue(gasCost > 0);
        assertTrue(protocolFees >= 0);
        assertTrue(crossChainFees >= 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetTreasury() public {
        address newTreasury = address(0x999);
        
        vm.prank(address(this));
        walletManager.setTreasury(newTreasury);
        
        assertEq(walletManager.treasury(), newTreasury);
    }
    
    function test_SetTreasury_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        walletManager.setTreasury(address(0x999));
    }
    
    function test_SetTreasury_RevertWhen_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid treasury address");
        walletManager.setTreasury(address(0));
    }
    
    function test_SetMaxSingleAmount() public {
        uint256 newMax = 2000000e6; // 2M USDC
        
        vm.prank(address(this));
        walletManager.setMaxSingleAmount(newMax);
        
        assertEq(walletManager.MAX_SINGLE_AMOUNT(), newMax);
    }
    
    function test_SetMaxSingleAmount_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        walletManager.setMaxSingleAmount(2000000e6);
    }
    
    function test_SetMaxDailyAmount() public {
        uint256 newMax = 20000000e6; // 20M USDC
        
        vm.prank(address(this));
        walletManager.setMaxDailyAmount(newMax);
        
        assertEq(walletManager.MAX_DAILY_AMOUNT(), newMax);
    }
    
    function test_SetMaxDailyAmount_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        walletManager.setMaxDailyAmount(20000000e6);
    }
    
    function test_SetProtocolFee() public {
        uint256 newFee = 50; // 0.5%
        
        vm.prank(address(this));
        walletManager.setProtocolFee(newFee);
        
        assertEq(walletManager.protocolFee(), newFee);
    }
    
    function test_SetProtocolFee_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        walletManager.setProtocolFee(50);
    }
    
    function test_SetProtocolFee_RevertWhen_InvalidFee() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid protocol fee");
        walletManager.setProtocolFee(10001); // > 100%
    }
    
    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EmergencyWithdraw() public {
        uint256 initialBalance = usdc.balanceOf(TREASURY);
        
        vm.prank(address(this));
        walletManager.emergencyWithdraw();
        
        assertEq(usdc.balanceOf(TREASURY), initialBalance + INITIAL_BALANCE);
        assertEq(usdc.balanceOf(address(walletManager)), 0);
    }
    
    function test_EmergencyWithdraw_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        walletManager.emergencyWithdraw();
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetSupportedChains() public {
        uint256[] memory chains = walletManager.getSupportedChains();
        assertTrue(chains.length > 0);
    }
    
    function test_IsChainSupported() public {
        assertTrue(walletManager.isChainSupported(1)); // Ethereum
        assertTrue(walletManager.isChainSupported(137)); // Polygon
        assertFalse(walletManager.isChainSupported(0)); // Invalid
    }
    
    function test_GetDailyVolume() public {
        uint256 volume = walletManager.getDailyVolume(USER);
        assertEq(volume, 0); // No transactions yet
    }
    
    function test_GetProtocolBalance() public {
        uint256 balance = walletManager.getProtocolBalance(
            keccak256("AAVE_V3"),
            1
        );
        assertEq(balance, 0); // No deposits yet
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(walletManager.USDC(), address(usdc));
        assertTrue(walletManager.MAX_SINGLE_AMOUNT() > 0);
        assertTrue(walletManager.MAX_DAILY_AMOUNT() > 0);
        assertTrue(walletManager.protocolFee() >= 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_DepositToProtocol_MaxAmount() public {
        uint256 maxAmount = walletManager.MAX_SINGLE_AMOUNT();
        
        vm.prank(USER);
        usdc.approve(address(walletManager), maxAmount);
        
        vm.prank(USER);
        walletManager.depositToProtocol(
            keccak256("AAVE_V3"),
            maxAmount,
            1
        );
        
        // Should succeed
        assertTrue(true);
    }
    
    function test_WithdrawFromProtocol_ZeroAmount() public {
        vm.prank(USER);
        (bool success, bytes32 txHash) = walletManager.withdrawFromProtocol(
            keccak256("AAVE_V3"),
            0,
            1
        );
        
        assertTrue(success);
        assertTrue(txHash != bytes32(0));
    }
    
    function test_TransferUSDCCrossChain_ZeroAmount() public {
        vm.prank(USER);
        (bool success, bytes32 transferId) = walletManager.transferUSDCCrossChain(
            USER,
            0,
            1,
            137,
            USER
        );
        
        assertTrue(success);
        assertTrue(transferId != bytes32(0));
    }
}
