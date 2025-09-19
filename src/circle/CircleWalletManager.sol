// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ICircleWalletManager.sol";
import "../interfaces/ICCTPIntegration.sol";

/**
 * @title CircleWalletManager
 * @author AVS Yield Labs
 * @notice Implementation of Circle Programmable Wallets for automated USDC yield optimization
 * @dev This contract manages Circle wallets, executes rebalancing operations, and integrates with CCTP
 */
contract CircleWalletManager is ICircleWalletManager, ReentrancyGuard, Ownable, Pausable {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC token address
    address public constant USDC = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
    
    /// @notice Maximum single transaction amount (1M USDC)
    uint256 public constant MAX_SINGLE_AMOUNT = 1_000_000e6;
    
    /// @notice Maximum daily transaction amount (10M USDC)
    uint256 public constant MAX_DAILY_AMOUNT = 10_000_000e6;
    
    /// @notice Minimum rebalancing amount (100 USDC)
    uint256 public constant MIN_REBALANCE_AMOUNT = 100e6;
    
    /// @notice Maximum slippage tolerance (5%)
    uint256 public constant MAX_SLIPPAGE = 500;
    
    /// @notice Rebalancing cooldown period (5 minutes)
    uint256 public constant REBALANCE_COOLDOWN = 300;
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice CCTP Integration contract
    ICCTPIntegration public immutable cctpIntegration;
    
    /// @notice User wallet configurations
    mapping(address => WalletConfig) public userWallets;
    
    /// @notice Rebalancing execution results
    mapping(bytes32 => ExecutionResult) public executionResults;
    
    /// @notice User rebalancing requests tracking
    mapping(address => bytes32[]) public userRequests;
    
    /// @notice Daily transaction amounts per user
    mapping(address => mapping(uint256 => uint256)) public dailyAmounts; // user => day => amount
    
    /// @notice Last rebalancing timestamp per user
    mapping(address => uint256) public lastRebalanceTime;
    
    /// @notice Automated rebalancing settings
    mapping(address => AutomationConfig) public automationConfigs;
    
    /// @notice Cross-chain transfer tracking
    mapping(bytes32 => CrossChainTransfer) public crossChainTransfers;
    
    /// @notice Supported protocols for rebalancing
    mapping(bytes32 => bool) public supportedProtocols;
    
    /// @notice Supported chains for cross-chain operations
    mapping(uint256 => bool) public supportedChains;
    
    /// @notice Request counter for unique IDs
    uint256 private requestCounter;
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct AutomationConfig {
        bool isEnabled;               // Whether automation is enabled
        uint256 frequency;            // Rebalancing frequency in seconds
        uint256 threshold;            // Minimum improvement threshold (bp)
        uint256 maxAmount;            // Maximum amount per rebalancing
        uint256 nextRebalanceTime;    // Next scheduled rebalancing
    }
    
    struct CrossChainTransfer {
        address userAddress;          // User initiating transfer
        uint256 amount;               // Transfer amount
        uint256 fromChainId;          // Source chain
        uint256 toChainId;            // Target chain
        address recipientAddress;     // Recipient on target chain
        uint256 timestamp;            // Transfer timestamp
        string status;                // Transfer status
        uint256 completedTimestamp;   // Completion timestamp
        string failureReason;         // Failure reason if failed
    }
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event RebalancingRequested(
        bytes32 indexed requestId,
        address indexed userAddress,
        bytes32 fromProtocol,
        bytes32 toProtocol,
        uint256 amount
    );
    
    event RebalancingCompleted(
        bytes32 indexed requestId,
        address indexed userAddress,
        uint256 amountExecuted,
        uint256 gasUsed
    );
    
    event RebalancingFailed(
        bytes32 indexed requestId,
        address indexed userAddress,
        string reason
    );
    
    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyWalletOwner(address userAddress) {
        require(msg.sender == userAddress || msg.sender == owner(), "Unauthorized access");
        _;
    }
    
    modifier validProtocol(bytes32 protocolId) {
        require(supportedProtocols[protocolId], "Unsupported protocol");
        _;
    }
    
    modifier validChain(uint256 chainId) {
        require(supportedChains[chainId], "Unsupported chain");
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        ICCTPIntegration _cctpIntegration
    ) Ownable(msg.sender) {
        if (address(_cctpIntegration) == address(0)) {
            revert("Invalid CCTP integration");
        }
        cctpIntegration = _cctpIntegration;
        
        // Initialize supported protocols
        supportedProtocols[keccak256("AAVE_V3")] = true;
        supportedProtocols[keccak256("COMPOUND_V3")] = true;
        supportedProtocols[keccak256("MORPHO")] = true;
        supportedProtocols[keccak256("MAKER_DSR")] = true;
        
        // Initialize supported chains
        supportedChains[1] = true;      // Ethereum
        supportedChains[8453] = true;   // Base
        supportedChains[42161] = true;  // Arbitrum
        supportedChains[137] = true;    // Polygon
        supportedChains[43114] = true;  // Avalanche
    }
    
    /*//////////////////////////////////////////////////////////////
                        WALLET MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    function setupUserWallet(
        address userAddress, 
        WalletConfig calldata config
    ) external override onlyWalletOwner(userAddress) returns (address walletAddress) {
        require(userAddress != address(0), "Invalid user address");
        require(config.walletAddress != address(0), "Invalid wallet address");
        require(config.maxSingleAmount <= MAX_SINGLE_AMOUNT, "Single amount too high");
        require(config.maxDailyAmount <= MAX_DAILY_AMOUNT, "Daily amount too high");
        
        userWallets[userAddress] = config;
        walletAddress = config.walletAddress;
        
        emit WalletCreated(userAddress, walletAddress);
        emit WalletConfigured(userAddress, config);
        
        return walletAddress;
    }
    
    function getUserWalletConfig(address userAddress) 
        external view override returns (WalletConfig memory config) {
        return userWallets[userAddress];
    }
    
    function updateWalletConfig(
        address userAddress, 
        WalletConfig calldata newConfig
    ) external override onlyWalletOwner(userAddress) {
        require(userWallets[userAddress].walletAddress != address(0), "Wallet not found");
        require(newConfig.maxSingleAmount <= MAX_SINGLE_AMOUNT, "Single amount too high");
        require(newConfig.maxDailyAmount <= MAX_DAILY_AMOUNT, "Daily amount too high");
        
        userWallets[userAddress] = newConfig;
        
        emit WalletConfigured(userAddress, newConfig);
    }
    
    function hasUserWallet(address userAddress) 
        external view override returns (bool hasWallet, address walletAddress) {
        WalletConfig memory config = userWallets[userAddress];
        hasWallet = config.walletAddress != address(0);
        walletAddress = config.walletAddress;
    }
    
    /*//////////////////////////////////////////////////////////////
                        REBALANCING EXECUTION
    //////////////////////////////////////////////////////////////*/
    
    function executeRebalancing(RebalanceRequest calldata request) 
        external override nonReentrant whenNotPaused returns (bytes32 requestId) {
        
        _validateRebalancingRequest(request);
        
        requestId = _generateRequestId();
        
        // Check daily limits
        uint256 today = block.timestamp / 86400;
        dailyAmounts[request.userAddress][today] += request.amount;
        require(
            dailyAmounts[request.userAddress][today] <= userWallets[request.userAddress].maxDailyAmount,
            "Daily limit exceeded"
        );
        
        // Check cooldown
        require(
            block.timestamp >= lastRebalanceTime[request.userAddress] + REBALANCE_COOLDOWN,
            "Rebalancing cooldown active"
        );
        
        // Store request for tracking
        userRequests[request.userAddress].push(requestId);
        
        // Execute the rebalancing
        ExecutionResult memory result = _executeRebalancingInternal(requestId, request);
        executionResults[requestId] = result;
        
        // Update last rebalancing time
        lastRebalanceTime[request.userAddress] = block.timestamp;
        
        emit RebalancingRequested(
            requestId,
            request.userAddress,
            request.fromProtocol,
            request.toProtocol,
            request.amount
        );
        
        if (result.success) {
            emit RebalancingCompleted(requestId, request.userAddress, result.amountExecuted, result.gasUsed);
        } else {
            emit RebalancingFailed(requestId, request.userAddress, result.errorMessage);
        }
        
        return requestId;
    }
    
    function executeBatchRebalancing(RebalanceRequest[] calldata requests) 
        external override nonReentrant whenNotPaused returns (bytes32[] memory requestIds) {
        
        requestIds = new bytes32[](requests.length);
        
        for (uint256 i = 0; i < requests.length; i++) {
            requestIds[i] = this.executeRebalancing(requests[i]);
        }
        
        return requestIds;
    }
    
    function getExecutionResult(bytes32 requestId) 
        external view override returns (ExecutionResult memory result) {
        return executionResults[requestId];
    }
    
    function cancelRebalancing(bytes32 requestId) 
        external override returns (bool success) {
        ExecutionResult storage result = executionResults[requestId];
        require(result.requestId == requestId, "Request not found");
        require(!result.success, "Cannot cancel completed request");
        
        // Mark as cancelled (simplified implementation)
        result.errorMessage = "Cancelled by user";
        
        return true;
    }
    
    /*//////////////////////////////////////////////////////////////
                        USDC OPERATIONS
    //////////////////////////////////////////////////////////////*/
    
    function depositToProtocol(
        address userAddress,
        bytes32 protocolId,
        uint256 amount,
        uint256 chainId
    ) external override validProtocol(protocolId) validChain(chainId) 
      returns (bool success, bytes32 transactionHash) {
        
        require(userWallets[userAddress].walletAddress != address(0), "Wallet not found");
        require(amount >= MIN_REBALANCE_AMOUNT, "Amount too small");
        
        // Simplified implementation - would integrate with actual protocol adapters
        transactionHash = keccak256(abi.encodePacked(userAddress, protocolId, amount, block.timestamp));
        success = true;
        
        return (success, transactionHash);
    }
    
    function withdrawFromProtocol(
        address userAddress,
        bytes32 protocolId,
        uint256 amount,
        uint256 chainId
    ) external override validProtocol(protocolId) validChain(chainId) 
      returns (bool success, bytes32 transactionHash) {
        
        require(userWallets[userAddress].walletAddress != address(0), "Wallet not found");
        require(amount > 0, "Invalid amount");
        
        // Simplified implementation - would integrate with actual protocol adapters
        transactionHash = keccak256(abi.encodePacked(userAddress, protocolId, amount, block.timestamp));
        success = true;
        
        return (success, transactionHash);
    }
    
    function getUserUSDCBalance(address userAddress) 
        external view override returns (
            uint256 totalBalance,
            bytes32[] memory protocolIds,
            uint256[] memory protocolAmounts,
            uint256[] memory chainIds,
            uint256[] memory chainAmounts
        ) {
        // This would need to be implemented with actual protocol queries
        // For now, return placeholders
        totalBalance = 0;
        protocolIds = new bytes32[](0);
        protocolAmounts = new uint256[](0);
        chainIds = new uint256[](0);
        chainAmounts = new uint256[](0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN OPERATIONS
    //////////////////////////////////////////////////////////////*/
    
    function transferUSDCCrossChain(
        address userAddress,
        uint256 amount,
        uint256 fromChainId,
        uint256 toChainId,
        address recipientAddress
    ) external override validChain(fromChainId) validChain(toChainId) 
      returns (bool success, bytes32 transferId) {
        
        require(userWallets[userAddress].walletAddress != address(0), "Wallet not found");
        require(amount > 0, "Invalid amount");
        require(fromChainId != toChainId, "Same chain transfer");
        require(recipientAddress != address(0), "Invalid recipient");
        
        transferId = keccak256(abi.encodePacked(userAddress, amount, fromChainId, toChainId, block.timestamp));
        
        crossChainTransfers[transferId] = CrossChainTransfer({
            userAddress: userAddress,
            amount: amount,
            fromChainId: fromChainId,
            toChainId: toChainId,
            recipientAddress: recipientAddress,
            timestamp: block.timestamp,
            status: "pending",
            completedTimestamp: 0,
            failureReason: ""
        });
        
        // Integration with CCTP would happen here
        success = true;
        
        emit CrossChainTransferInitiated(transferId, userAddress, amount, fromChainId, toChainId);
        
        return (success, transferId);
    }
    
    function getCrossChainTransferStatus(bytes32 transferId) 
        external view override returns (
            string memory status,
            uint256 completedTimestamp,
            string memory failureReason
        ) {
        CrossChainTransfer memory transfer = crossChainTransfers[transferId];
        return (transfer.status, transfer.completedTimestamp, transfer.failureReason);
    }
    
    /*//////////////////////////////////////////////////////////////
                        AUTOMATION & SCHEDULING
    //////////////////////////////////////////////////////////////*/
    
    function setupAutomatedRebalancing(
        address userAddress,
        uint256 frequency,
        uint256 threshold,
        uint256 maxAmount
    ) external override onlyWalletOwner(userAddress) {
        require(frequency >= 3600, "Frequency too high"); // Minimum 1 hour
        require(threshold >= 10 && threshold <= 2000, "Invalid threshold"); // 0.1% to 20%
        require(maxAmount <= userWallets[userAddress].maxSingleAmount, "Amount exceeds limit");
        
        automationConfigs[userAddress] = AutomationConfig({
            isEnabled: true,
            frequency: frequency,
            threshold: threshold,
            maxAmount: maxAmount,
            nextRebalanceTime: block.timestamp + frequency
        });
        
        emit AutomatedRebalancingEnabled(userAddress, frequency, threshold);
    }
    
    function disableAutomatedRebalancing(address userAddress) 
        external override onlyWalletOwner(userAddress) {
        automationConfigs[userAddress].isEnabled = false;
        
        emit AutomatedRebalancingDisabled(userAddress);
    }
    
    function getAutomationStatus(address userAddress) 
        external view override returns (bool isEnabled, uint256 nextRebalanceTime) {
        AutomationConfig memory config = automationConfigs[userAddress];
        return (config.isEnabled, config.nextRebalanceTime);
    }
    
    /*//////////////////////////////////////////////////////////////
                            GAS & FEES
    //////////////////////////////////////////////////////////////*/
    
    function enableUSDCGasPayments(address userAddress, uint256 maxGasPerTransaction) 
        external override onlyWalletOwner(userAddress) {
        require(maxGasPerTransaction > 0, "Invalid gas limit");
        
        // Implementation would configure Circle wallet for USDC gas payments
        
        emit USDCGasPaymentEnabled(userAddress, maxGasPerTransaction);
    }
    
    function estimateRebalancingCost(RebalanceRequest calldata request) 
        external view override returns (uint256 estimatedGasCost, uint256 confidence) {
        
        // Simplified gas estimation
        uint256 baseGas = 150000; // Base gas for rebalancing
        
        if (request.fromChainId != request.toChainId) {
            baseGas += 200000; // Additional gas for cross-chain
        }
        
        // Convert to USDC equivalent (simplified)
        estimatedGasCost = (baseGas * 20 gwei * 2000) / 1e18; // Rough USDC equivalent
        confidence = 7500; // 75% confidence
        
        return (estimatedGasCost, confidence);
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _validateRebalancingRequest(RebalanceRequest calldata request) internal view {
        require(userWallets[request.userAddress].walletAddress != address(0), "Wallet not found");
        require(supportedProtocols[request.fromProtocol], "Source protocol not supported");
        require(supportedProtocols[request.toProtocol], "Target protocol not supported");
        require(supportedChains[request.fromChainId], "Source chain not supported");
        require(supportedChains[request.toChainId], "Target chain not supported");
        require(request.amount >= MIN_REBALANCE_AMOUNT, "Amount too small");
        require(request.amount <= userWallets[request.userAddress].maxSingleAmount, "Amount exceeds limit");
        require(request.maxSlippage <= MAX_SLIPPAGE, "Slippage too high");
        require(request.deadline > block.timestamp, "Deadline passed");
        
        WalletConfig memory config = userWallets[request.userAddress];
        require(config.autoRebalanceEnabled, "Auto-rebalancing disabled");
        
        // Check if protocols are approved
        bool fromProtocolApproved = false;
        bool toProtocolApproved = false;
        
        for (uint256 i = 0; i < config.approvedProtocols.length; i++) {
            if (config.approvedProtocols[i] == request.fromProtocol) {
                fromProtocolApproved = true;
            }
            if (config.approvedProtocols[i] == request.toProtocol) {
                toProtocolApproved = true;
            }
        }
        
        require(fromProtocolApproved, "Source protocol not approved");
        require(toProtocolApproved, "Target protocol not approved");
    }
    
    function _executeRebalancingInternal(
        bytes32 requestId, 
        RebalanceRequest calldata request
    ) internal returns (ExecutionResult memory result) {
        
        uint256 gasStart = gasleft();
        
        try this._performRebalancing(request) returns (uint256 amountExecuted) {
            result = ExecutionResult({
                requestId: requestId,
                success: true,
                amountExecuted: amountExecuted,
                gasUsed: gasStart - gasleft(),
                feesPaid: 0, // Would be calculated
                transactionHash: keccak256(abi.encodePacked(requestId, block.timestamp)),
                errorMessage: ""
            });
        } catch Error(string memory reason) {
            result = ExecutionResult({
                requestId: requestId,
                success: false,
                amountExecuted: 0,
                gasUsed: gasStart - gasleft(),
                feesPaid: 0,
                transactionHash: bytes32(0),
                errorMessage: reason
            });
        }
        
        return result;
    }
    
    function _performRebalancing(RebalanceRequest calldata request) 
        external returns (uint256 amountExecuted) {
        // This function would contain the actual rebalancing logic
        // For now, simulate successful execution
        return request.amount;
    }
    
    function _generateRequestId() internal returns (bytes32) {
        return keccak256(abi.encodePacked(++requestCounter, block.timestamp, msg.sender));
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function addSupportedProtocol(bytes32 protocolId) external onlyOwner {
        supportedProtocols[protocolId] = true;
    }
    
    function removeSupportedProtocol(bytes32 protocolId) external onlyOwner {
        supportedProtocols[protocolId] = false;
    }
    
    function addSupportedChain(uint256 chainId) external onlyOwner {
        supportedChains[chainId] = true;
    }
    
    function removeSupportedChain(uint256 chainId) external onlyOwner {
        supportedChains[chainId] = false;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
}