// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title ICCTPIntegration
 * @notice Interface for Circle's Cross-Chain Transfer Protocol (CCTP) v2 integration
 * @dev This interface provides methods for native USDC cross-chain transfers with hooks
 */
interface ICCTPIntegration {
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct TransferParams {
        address sender;               // Sender address
        address recipient;            // Recipient address on destination chain
        uint256 amount;               // Amount of USDC to transfer
        uint32 destinationDomain;     // CCTP destination domain
        bytes32 destinationCaller;    // Authorized caller on destination (optional)
        bytes hookData;               // Data to pass to destination hook
    }
    
    struct FastTransferParams {
        address sender;               // Sender address
        address recipient;            // Recipient address on destination chain
        uint256 amount;               // Amount of USDC to transfer
        uint32 destinationDomain;     // CCTP destination domain
        uint256 maxFee;               // Maximum acceptable fast transfer fee
        bytes hookData;               // Data to pass to destination hook
    }
    
    struct TransferStatus {
        bytes32 messageHash;          // CCTP message hash
        uint256 timestamp;            // Transfer initiation timestamp
        uint32 sourceDomain;          // Source domain
        uint32 destinationDomain;     // Destination domain
        uint256 amount;               // Transfer amount
        address sender;               // Sender address
        address recipient;            // Recipient address
        bool isCompleted;             // Whether transfer is completed
        bool isFastTransfer;          // Whether this was a fast transfer
        uint256 completedTimestamp;   // When transfer was completed
        bytes32 attestation;          // Circle attestation
    }
    
    struct DomainInfo {
        uint32 domain;                // CCTP domain identifier
        uint256 chainId;              // Chain ID
        string name;                  // Chain name
        address tokenMessenger;       // TokenMessenger contract address
        address messageTransmitter;   // MessageTransmitter contract address
        bool isSupported;             // Whether domain is supported
        bool fastTransferEnabled;     // Whether fast transfers are enabled
        uint256 minTransferAmount;    // Minimum transfer amount
        uint256 maxTransferAmount;    // Maximum transfer amount
    }
    
    /*//////////////////////////////////////////////////////////////
                        STANDARD TRANSFERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initiate a standard CCTP transfer
     * @param params Transfer parameters
     * @return messageHash CCTP message hash for tracking
     */
    function initiateTransfer(TransferParams calldata params)
        external returns (bytes32 messageHash);
    
    /**
     * @notice Initiate a CCTP transfer with automatic execution on destination
     * @param params Transfer parameters
     * @param targetContract Contract to call on destination chain
     * @param targetCalldata Calldata for destination contract
     * @return messageHash CCTP message hash for tracking
     */
    function transferAndExecute(
        TransferParams calldata params,
        address targetContract,
        bytes calldata targetCalldata
    ) external returns (bytes32 messageHash);
    
    /**
     * @notice Complete a CCTP transfer on destination chain
     * @param message CCTP message
     * @param attestation Circle attestation
     * @return success Whether completion was successful
     */
    function completeTransfer(bytes calldata message, bytes calldata attestation)
        external returns (bool success);
    
    /*//////////////////////////////////////////////////////////////
                        FAST TRANSFERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initiate a fast CCTP transfer (faster than finality)
     * @param params Fast transfer parameters
     * @return messageHash CCTP message hash for tracking
     */
    function initiateFastTransfer(FastTransferParams calldata params)
        external returns (bytes32 messageHash);
    
    /**
     * @notice Get fast transfer fee estimate
     * @param amount Transfer amount
     * @param destinationDomain Target domain
     * @return fee Estimated fast transfer fee
     * @return maxFee Maximum possible fee
     */
    function getFastTransferFee(uint256 amount, uint32 destinationDomain)
        external view returns (uint256 fee, uint256 maxFee);
    
    /**
     * @notice Check if fast transfer is available for domain pair
     * @param sourceDomain Source domain
     * @param destinationDomain Destination domain
     * @return isAvailable Whether fast transfer is available
     * @return estimatedTime Estimated completion time in seconds
     */
    function isFastTransferAvailable(uint32 sourceDomain, uint32 destinationDomain)
        external view returns (bool isAvailable, uint256 estimatedTime);
    
    /*//////////////////////////////////////////////////////////////
                        YIELD OPTIMIZATION HOOKS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Transfer USDC and execute yield optimization on destination
     * @param params Transfer parameters
     * @param yieldProtocol Target yield protocol on destination
     * @param optimizationData Yield optimization parameters
     * @return messageHash CCTP message hash for tracking
     */
    function transferAndOptimizeYield(
        TransferParams calldata params,
        bytes32 yieldProtocol,
        bytes calldata optimizationData
    ) external returns (bytes32 messageHash);
    
    /**
     * @notice Fast transfer with yield optimization hook
     * @param params Fast transfer parameters
     * @param yieldProtocol Target yield protocol on destination
     * @param optimizationData Yield optimization parameters
     * @return messageHash CCTP message hash for tracking
     */
    function fastTransferAndOptimizeYield(
        FastTransferParams calldata params,
        bytes32 yieldProtocol,
        bytes calldata optimizationData
    ) external returns (bytes32 messageHash);
    
    /*//////////////////////////////////////////////////////////////
                        TRANSFER TRACKING
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get transfer status
     * @param messageHash CCTP message hash
     * @return status Transfer status information
     */
    function getTransferStatus(bytes32 messageHash)
        external view returns (TransferStatus memory status);
    
    /**
     * @notice Get transfer history for an address
     * @param userAddress User address
     * @param limit Maximum number of transfers to return
     * @param offset Offset for pagination
     * @return transfers Array of transfer statuses
     */
    function getTransferHistory(address userAddress, uint256 limit, uint256 offset)
        external view returns (TransferStatus[] memory transfers);
    
    /**
     * @notice Get pending transfers for an address
     * @param userAddress User address
     * @return pendingTransfers Array of pending transfer message hashes
     */
    function getPendingTransfers(address userAddress)
        external view returns (bytes32[] memory pendingTransfers);
    
    /*//////////////////////////////////////////////////////////////
                        DOMAIN MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get supported domains
     * @return domains Array of supported domain information
     */
    function getSupportedDomains()
        external view returns (DomainInfo[] memory domains);
    
    /**
     * @notice Get domain info by chain ID
     * @param chainId Chain ID
     * @return info Domain information
     */
    function getDomainByChainId(uint256 chainId)
        external view returns (DomainInfo memory info);
    
    /**
     * @notice Convert chain ID to CCTP domain
     * @param chainId Chain ID
     * @return domain CCTP domain identifier
     */
    function chainIdToDomain(uint256 chainId)
        external view returns (uint32 domain);
    
    /**
     * @notice Convert CCTP domain to chain ID
     * @param domain CCTP domain identifier
     * @return chainId Chain ID
     */
    function domainToChainId(uint32 domain)
        external view returns (uint256 chainId);
    
    /*//////////////////////////////////////////////////////////////
                        ATTESTATION SERVICES
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get Circle attestation for a message
     * @param messageHash CCTP message hash
     * @return attestation Circle attestation bytes
     * @return isReady Whether attestation is ready
     */
    function getAttestation(bytes32 messageHash)
        external view returns (bytes memory attestation, bool isReady);
    
    /**
     * @notice Wait for attestation with timeout
     * @param messageHash CCTP message hash
     * @param timeout Maximum wait time in seconds
     * @return attestation Circle attestation bytes
     * @return success Whether attestation was received within timeout
     */
    function waitForAttestation(bytes32 messageHash, uint256 timeout)
        external returns (bytes memory attestation, bool success);
    
    /*//////////////////////////////////////////////////////////////
                        UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calculate transfer time estimate
     * @param sourceDomain Source domain
     * @param destinationDomain Destination domain
     * @param isFastTransfer Whether using fast transfer
     * @return estimatedTime Estimated completion time in seconds
     */
    function getTransferTimeEstimate(
        uint32 sourceDomain,
        uint32 destinationDomain,
        bool isFastTransfer
    ) external view returns (uint256 estimatedTime);
    
    /**
     * @notice Get transfer limits for domain pair
     * @param sourceDomain Source domain
     * @param destinationDomain Destination domain
     * @return minAmount Minimum transfer amount
     * @return maxAmount Maximum transfer amount
     * @return dailyLimit Daily transfer limit
     */
    function getTransferLimits(uint32 sourceDomain, uint32 destinationDomain)
        external view returns (uint256 minAmount, uint256 maxAmount, uint256 dailyLimit);
    
    /**
     * @notice Check if address has sufficient allowance for transfer
     * @param userAddress User address
     * @param amount Transfer amount
     * @return hasAllowance Whether user has sufficient allowance
     * @return currentAllowance Current USDC allowance
     */
    function checkTransferAllowance(address userAddress, uint256 amount)
        external view returns (bool hasAllowance, uint256 currentAllowance);
    
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TransferInitiated(
        bytes32 indexed messageHash,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint32 sourceDomain,
        uint32 destinationDomain
    );
    
    event FastTransferInitiated(
        bytes32 indexed messageHash,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint32 sourceDomain,
        uint32 destinationDomain,
        uint256 fee
    );
    
    event TransferCompleted(
        bytes32 indexed messageHash,
        address indexed recipient,
        uint256 amount
    );
    
    event YieldOptimizationExecuted(
        bytes32 indexed messageHash,
        address indexed recipient,
        bytes32 indexed yieldProtocol,
        uint256 amount
    );
    
    event AttestationReceived(
        bytes32 indexed messageHash,
        bytes32 indexed attestationHash
    );
    
    event DomainAdded(
        uint32 indexed domain,
        uint256 indexed chainId,
        string name
    );
    
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error UnsupportedDomain();
    error InvalidAmount();
    error InsufficientAllowance();
    error TransferFailed();
    error AttestationNotReady();
    error AttestationTimeout();
    error FastTransferNotAvailable();
    error ExcessiveFee();
    error TransferLimitExceeded();
    error InvalidDestinationCaller();
    error HookExecutionFailed();
}