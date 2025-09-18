// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title ICircleWalletManager
 * @notice Interface for Circle Programmable Wallets integration
 * @dev This interface defines methods for automated USDC management through Circle Wallets
 */
interface ICircleWalletManager {
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct WalletConfig {
        address walletAddress;        // Circle wallet address
        bool isDeveloperControlled;   // Whether wallet is developer-controlled
        bool isUserControlled;        // Whether wallet is user-controlled
        uint256 maxDailyAmount;       // Maximum daily transaction amount
        uint256 maxSingleAmount;      // Maximum single transaction amount
        bytes32[] approvedProtocols;  // Whitelisted protocols for this wallet
        uint256[] approvedChains;     // Whitelisted chains for this wallet
        bool autoRebalanceEnabled;    // Whether auto-rebalancing is enabled
    }
    
    struct RebalanceRequest {
        address userAddress;          // User requesting rebalance
        bytes32 fromProtocol;         // Source protocol
        bytes32 toProtocol;           // Target protocol
        uint256 amount;               // Amount to rebalance
        uint256 fromChainId;          // Source chain
        uint256 toChainId;            // Target chain
        uint256 maxSlippage;          // Maximum acceptable slippage
        uint256 deadline;             // Transaction deadline
        bytes additionalData;         // Protocol-specific data
    }
    
    struct ExecutionResult {
        bytes32 requestId;            // Request identifier
        bool success;                 // Whether execution was successful
        uint256 amountExecuted;       // Actual amount executed
        uint256 gasUsed;              // Gas used for execution
        uint256 feesPaid;             // Total fees paid
        bytes32 transactionHash;      // Transaction hash
        string errorMessage;          // Error message if failed
    }
    
    /*//////////////////////////////////////////////////////////////
                        WALLET MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Create or configure a Circle wallet for a user
     * @param userAddress User address
     * @param config Wallet configuration
     * @return walletAddress Address of the created/configured wallet
     */
    function setupUserWallet(address userAddress, WalletConfig calldata config)
        external returns (address walletAddress);
    
    /**
     * @notice Get wallet configuration for a user
     * @param userAddress User address
     * @return config Current wallet configuration
     */
    function getUserWalletConfig(address userAddress)
        external view returns (WalletConfig memory config);
    
    /**
     * @notice Update wallet configuration
     * @param userAddress User address
     * @param newConfig Updated configuration
     */
    function updateWalletConfig(address userAddress, WalletConfig calldata newConfig)
        external;
    
    /**
     * @notice Check if user has a configured wallet
     * @param userAddress User address
     * @return hasWallet Whether user has a wallet
     * @return walletAddress Wallet address if exists
     */
    function hasUserWallet(address userAddress)
        external view returns (bool hasWallet, address walletAddress);
    
    /*//////////////////////////////////////////////////////////////
                        REBALANCING EXECUTION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Execute USDC rebalancing for a user
     * @param request Rebalancing request details
     * @return requestId Request identifier for tracking
     */
    function executeRebalancing(RebalanceRequest calldata request)
        external returns (bytes32 requestId);
    
    /**
     * @notice Execute batch rebalancing for multiple users
     * @param requests Array of rebalancing requests
     * @return requestIds Array of request identifiers
     */
    function executeBatchRebalancing(RebalanceRequest[] calldata requests)
        external returns (bytes32[] memory requestIds);
    
    /**
     * @notice Get execution result for a request
     * @param requestId Request identifier
     * @return result Execution result details
     */
    function getExecutionResult(bytes32 requestId)
        external view returns (ExecutionResult memory result);
    
    /**
     * @notice Cancel a pending rebalancing request
     * @param requestId Request identifier
     * @return success Whether cancellation was successful
     */
    function cancelRebalancing(bytes32 requestId)
        external returns (bool success);
    
    /*//////////////////////////////////////////////////////////////
                        USDC OPERATIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deposit USDC into a yield protocol via Circle wallet
     * @param userAddress User address
     * @param protocolId Target protocol
     * @param amount Amount to deposit
     * @param chainId Target chain ID
     * @return success Whether deposit was successful
     * @return transactionHash Transaction hash
     */
    function depositToProtocol(
        address userAddress,
        bytes32 protocolId,
        uint256 amount,
        uint256 chainId
    ) external returns (bool success, bytes32 transactionHash);
    
    /**
     * @notice Withdraw USDC from a yield protocol via Circle wallet
     * @param userAddress User address
     * @param protocolId Source protocol
     * @param amount Amount to withdraw
     * @param chainId Source chain ID
     * @return success Whether withdrawal was successful
     * @return transactionHash Transaction hash
     */
    function withdrawFromProtocol(
        address userAddress,
        bytes32 protocolId,
        uint256 amount,
        uint256 chainId
    ) external returns (bool success, bytes32 transactionHash);
    
    /**
     * @notice Get USDC balance across all protocols for a user
     * @param userAddress User address
     * @return totalBalance Total USDC balance
     * @return protocolIds Array of protocol IDs
     * @return protocolAmounts Array of protocol amounts
     * @return chainIds Array of chain IDs
     * @return chainAmounts Array of chain amounts
     */
    function getUserUSDCBalance(address userAddress)
        external view returns (
            uint256 totalBalance,
            bytes32[] memory protocolIds,
            uint256[] memory protocolAmounts,
            uint256[] memory chainIds,
            uint256[] memory chainAmounts
        );
    
    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN OPERATIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Transfer USDC between chains using CCTP
     * @param userAddress User address
     * @param amount Amount to transfer
     * @param fromChainId Source chain ID
     * @param toChainId Target chain ID
     * @param recipientAddress Recipient address on target chain
     * @return success Whether transfer was initiated
     * @return transferId CCTP transfer identifier
     */
    function transferUSDCCrossChain(
        address userAddress,
        uint256 amount,
        uint256 fromChainId,
        uint256 toChainId,
        address recipientAddress
    ) external returns (bool success, bytes32 transferId);
    
    /**
     * @notice Get cross-chain transfer status
     * @param transferId CCTP transfer identifier
     * @return status Transfer status (pending, completed, failed)
     * @return completedTimestamp When transfer was completed
     * @return failureReason Failure reason if failed
     */
    function getCrossChainTransferStatus(bytes32 transferId)
        external view returns (
            string memory status,
            uint256 completedTimestamp,
            string memory failureReason
        );
    
    /*//////////////////////////////////////////////////////////////
                        AUTOMATION & SCHEDULING
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Set up automated rebalancing for a user
     * @param userAddress User address
     * @param frequency Rebalancing frequency (in seconds)
     * @param threshold Minimum improvement threshold (basis points)
     * @param maxAmount Maximum amount per rebalancing
     */
    function setupAutomatedRebalancing(
        address userAddress,
        uint256 frequency,
        uint256 threshold,
        uint256 maxAmount
    ) external;
    
    /**
     * @notice Disable automated rebalancing for a user
     * @param userAddress User address
     */
    function disableAutomatedRebalancing(address userAddress) external;
    
    /**
     * @notice Check if automated rebalancing is enabled for user
     * @param userAddress User address
     * @return isEnabled Whether automation is enabled
     * @return nextRebalanceTime When next rebalancing is scheduled
     */
    function getAutomationStatus(address userAddress)
        external view returns (bool isEnabled, uint256 nextRebalanceTime);
    
    /*//////////////////////////////////////////////////////////////
                            GAS & FEES
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Enable USDC gas payments for a user's wallet
     * @param userAddress User address
     * @param maxGasPerTransaction Maximum gas fee per transaction (in USDC)
     */
    function enableUSDCGasPayments(address userAddress, uint256 maxGasPerTransaction)
        external;
    
    /**
     * @notice Get estimated gas cost in USDC for a rebalancing operation
     * @param request Rebalancing request
     * @return estimatedGasCost Estimated gas cost in USDC
     * @return confidence Confidence level of estimate (0-10000)
     */
    function estimateRebalancingCost(RebalanceRequest calldata request)
        external view returns (uint256 estimatedGasCost, uint256 confidence);
    
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event WalletCreated(address indexed userAddress, address indexed walletAddress);
    event WalletConfigured(address indexed userAddress, WalletConfig config);
    event RebalancingExecuted(
        bytes32 indexed requestId,
        address indexed userAddress,
        bytes32 indexed fromProtocol,
        bytes32 toProtocol,
        uint256 amount
    );
    event CrossChainTransferInitiated(
        bytes32 indexed transferId,
        address indexed userAddress,
        uint256 amount,
        uint256 fromChainId,
        uint256 toChainId
    );
    event AutomatedRebalancingEnabled(
        address indexed userAddress,
        uint256 frequency,
        uint256 threshold
    );
    event AutomatedRebalancingDisabled(address indexed userAddress);
    event USDCGasPaymentEnabled(address indexed userAddress, uint256 maxGasPerTransaction);
    
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error WalletNotFound();
    error InsufficientBalance();
    error InvalidConfiguration();
    error UnauthorizedAccess();
    error RebalancingNotAllowed();
    error UnsupportedProtocol();
    error UnsupportedChain();
    error ExcessiveSlippage();
    error DeadlineExceeded();
    error CrossChainTransferFailed();
    error AutomationNotEnabled();
    error GasPaymentNotEnabled();
}