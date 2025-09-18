// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ICCTPIntegration.sol";

/**
 * @title CCTPIntegration
 * @author AVS Yield Labs
 * @notice Implementation of Circle's Cross-Chain Transfer Protocol (CCTP) v2 for USDC yield optimization
 * @dev This contract facilitates native USDC transfers across chains with yield optimization hooks
 */
contract CCTPIntegration is ICCTPIntegration, ReentrancyGuard, Ownable, Pausable {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC token address
    address public constant USDC = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
    
    /// @notice Minimum transfer amount (1 USDC)
    uint256 public constant MIN_TRANSFER_AMOUNT = 1e6;
    
    /// @notice Maximum transfer amount (10M USDC)
    uint256 public constant MAX_TRANSFER_AMOUNT = 10_000_000e6;
    
    /// @notice Fast transfer fee cap (1%)
    uint256 public constant MAX_FAST_TRANSFER_FEE = 100;
    
    /// @notice Standard transfer time estimate (20 minutes)
    uint256 public constant STANDARD_TRANSFER_TIME = 1200;
    
    /// @notice Fast transfer time estimate (30 seconds)
    uint256 public constant FAST_TRANSFER_TIME = 30;
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Supported CCTP domains
    mapping(uint32 => DomainInfo) public domains;
    
    /// @notice Chain ID to domain mapping
    mapping(uint256 => uint32) public chainIdToDomainMapping;
    
    /// @notice Domain to chain ID mapping
    mapping(uint32 => uint256) public domainToChainIdMapping;
    
    /// @notice Transfer status tracking
    mapping(bytes32 => TransferStatus) public transferStatuses;
    
    /// @notice User transfer history
    mapping(address => bytes32[]) public userTransfers;
    
    /// @notice Pending transfers per user
    mapping(address => bytes32[]) public pendingTransfersByUser;
    
    /// @notice Circle attestations
    mapping(bytes32 => bytes) public attestations;
    
    /// @notice Daily transfer amounts per user per domain
    mapping(address => mapping(uint32 => mapping(uint256 => uint256))) public dailyTransferAmounts;
    
    /// @notice Fast transfer fee percentages by domain pair (in basis points)
    mapping(uint32 => mapping(uint32 => uint256)) public fastTransferFees;
    
    /// @notice Message hash counter for unique IDs
    uint256 private messageCounter;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TransferStatusUpdated(
        bytes32 indexed messageHash,
        bool isCompleted,
        uint256 timestamp
    );
    
    event DomainConfigured(
        uint32 indexed domain,
        uint256 indexed chainId,
        bool fastTransferEnabled
    );
    
    event FastTransferFeeUpdated(
        uint32 indexed sourceDomain,
        uint32 indexed destinationDomain,
        uint256 feePercentage
    );
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor() Ownable(msg.sender) {
        _initializeDomains();
    }
    
    /*//////////////////////////////////////////////////////////////
                        STANDARD TRANSFERS
    //////////////////////////////////////////////////////////////*/
    
    function initiateTransfer(TransferParams calldata params) 
        external override nonReentrant whenNotPaused returns (bytes32 messageHash) {
        
        _validateTransferParams(params);
        
        messageHash = _generateMessageHash();
        
        // Check daily limits
        uint32 sourceDomain = chainIdToDomainMapping[block.chainid];
        uint256 today = block.timestamp / 86400;
        dailyTransferAmounts[params.sender][sourceDomain][today] += params.amount;
        
        DomainInfo memory sourceInfo = domains[sourceDomain];
        require(
            dailyTransferAmounts[params.sender][sourceDomain][today] <= sourceInfo.maxTransferAmount,
            "Daily transfer limit exceeded"
        );
        
        // Transfer USDC from sender
        IERC20(USDC).transferFrom(params.sender, address(this), params.amount);
        
        // Store transfer status
        transferStatuses[messageHash] = TransferStatus({
            messageHash: messageHash,
            timestamp: block.timestamp,
            sourceDomain: sourceDomain,
            destinationDomain: params.destinationDomain,
            amount: params.amount,
            sender: params.sender,
            recipient: params.recipient,
            isCompleted: false,
            isFastTransfer: false,
            completedTimestamp: 0,
            attestation: bytes32(0)
        });
        
        // Add to user tracking
        userTransfers[params.sender].push(messageHash);
        pendingTransfersByUser[params.sender].push(messageHash);
        
        emit TransferInitiated(
            messageHash,
            params.sender,
            params.recipient,
            params.amount,
            sourceDomain,
            params.destinationDomain
        );
        
        // Simulate CCTP message sending (in real implementation, would call TokenMessenger)
        _simulateCCTPMessage(messageHash, params);
        
        return messageHash;
    }
    
    function transferAndExecute(
        TransferParams calldata params,
        address targetContract,
        bytes calldata targetCalldata
    ) external override nonReentrant whenNotPaused returns (bytes32 messageHash) {
        
        require(targetContract != address(0), "Invalid target contract");
        require(targetCalldata.length > 0, "Empty calldata");
        
        // Initiate standard transfer
        messageHash = this.initiateTransfer(params);
        
        // Store execution data (would be included in CCTP message)
        // In real implementation, this would be part of the CCTP message payload
        
        return messageHash;
    }
    
    function completeTransfer(bytes calldata message, bytes calldata attestation) 
        external override nonReentrant returns (bool success) {
        
        require(message.length > 0, "Empty message");
        require(attestation.length > 0, "Empty attestation");
        
        // Extract message hash from CCTP message (simplified)
        bytes32 messageHash = keccak256(message);
        
        TransferStatus storage status = transferStatuses[messageHash];
        require(status.messageHash == messageHash, "Transfer not found");
        require(!status.isCompleted, "Transfer already completed");
        
        // Verify attestation (simplified - in real implementation would verify Circle signature)
        require(_verifyAttestation(messageHash, attestation), "Invalid attestation");
        
        // Mark as completed
        status.isCompleted = true;
        status.completedTimestamp = block.timestamp;
        status.attestation = keccak256(attestation);
        
        // Remove from pending transfers
        _removePendingTransfer(status.sender, messageHash);
        
        // Transfer USDC to recipient (simplified - in real implementation CCTP handles this)
        IERC20(USDC).transfer(status.recipient, status.amount);
        
        emit TransferCompleted(messageHash, status.recipient, status.amount);
        emit TransferStatusUpdated(messageHash, true, block.timestamp);
        
        return true;
    }
    
    /*//////////////////////////////////////////////////////////////
                        FAST TRANSFERS
    //////////////////////////////////////////////////////////////*/
    
    function initiateFastTransfer(FastTransferParams calldata params) 
        external override nonReentrant whenNotPaused returns (bytes32 messageHash) {
        
        _validateFastTransferParams(params);
        
        messageHash = _generateMessageHash();
        
        uint32 sourceDomain = chainIdToDomainMapping[block.chainid];
        
        // Calculate fast transfer fee
        uint256 fee = _calculateFastTransferFee(params.amount, sourceDomain, params.destinationDomain);
        require(fee <= params.maxFee, "Fee exceeds maximum");
        
        uint256 netAmount = params.amount - fee;
        
        // Transfer USDC from sender
        IERC20(USDC).transferFrom(params.sender, address(this), params.amount);
        
        // Store transfer status
        transferStatuses[messageHash] = TransferStatus({
            messageHash: messageHash,
            timestamp: block.timestamp,
            sourceDomain: sourceDomain,
            destinationDomain: params.destinationDomain,
            amount: netAmount,
            sender: params.sender,
            recipient: params.recipient,
            isCompleted: false,
            isFastTransfer: true,
            completedTimestamp: 0,
            attestation: bytes32(0)
        });
        
        // Add to user tracking
        userTransfers[params.sender].push(messageHash);
        pendingTransfersByUser[params.sender].push(messageHash);
        
        emit FastTransferInitiated(
            messageHash,
            params.sender,
            params.recipient,
            netAmount,
            sourceDomain,
            params.destinationDomain,
            fee
        );
        
        // Simulate fast execution (would integrate with fast transfer providers)
        _simulateFastTransfer(messageHash, params, fee);
        
        return messageHash;
    }
    
    function getFastTransferFee(uint256 amount, uint32 destinationDomain) 
        external view override returns (uint256 fee, uint256 maxFee) {
        
        uint32 sourceDomain = chainIdToDomainMapping[block.chainid];
        fee = _calculateFastTransferFee(amount, sourceDomain, destinationDomain);
        maxFee = (amount * MAX_FAST_TRANSFER_FEE) / 10000;
        
        return (fee, maxFee);
    }
    
    function isFastTransferAvailable(uint32 sourceDomain, uint32 destinationDomain) 
        external view override returns (bool isAvailable, uint256 estimatedTime) {
        
        DomainInfo memory sourceInfo = domains[sourceDomain];
        DomainInfo memory destInfo = domains[destinationDomain];
        
        isAvailable = sourceInfo.fastTransferEnabled && 
                     destInfo.fastTransferEnabled && 
                     sourceInfo.isSupported && 
                     destInfo.isSupported;
        
        estimatedTime = isAvailable ? FAST_TRANSFER_TIME : STANDARD_TRANSFER_TIME;
        
        return (isAvailable, estimatedTime);
    }
    
    /*//////////////////////////////////////////////////////////////
                        YIELD OPTIMIZATION HOOKS
    //////////////////////////////////////////////////////////////*/
    
    function transferAndOptimizeYield(
        TransferParams calldata params,
        bytes32 yieldProtocol,
        bytes calldata optimizationData
    ) external override nonReentrant whenNotPaused returns (bytes32 messageHash) {
        
        require(yieldProtocol != bytes32(0), "Invalid yield protocol");
        require(optimizationData.length > 0, "Empty optimization data");
        
        // Initiate standard transfer with yield optimization hook
        messageHash = this.initiateTransfer(params);
        
        // Store yield optimization parameters
        // In real implementation, this would be included in CCTP message for destination execution
        
        emit YieldOptimizationExecuted(messageHash, params.recipient, yieldProtocol, params.amount);
        
        return messageHash;
    }
    
    function fastTransferAndOptimizeYield(
        FastTransferParams calldata params,
        bytes32 yieldProtocol,
        bytes calldata optimizationData
    ) external override nonReentrant whenNotPaused returns (bytes32 messageHash) {
        
        require(yieldProtocol != bytes32(0), "Invalid yield protocol");
        require(optimizationData.length > 0, "Empty optimization data");
        
        // Initiate fast transfer with yield optimization hook
        messageHash = this.initiateFastTransfer(params);
        
        // Store yield optimization parameters
        // In real implementation, this would be included in fast transfer message
        
        emit YieldOptimizationExecuted(messageHash, params.recipient, yieldProtocol, params.amount);
        
        return messageHash;
    }
    
    /*//////////////////////////////////////////////////////////////
                        TRANSFER TRACKING
    //////////////////////////////////////////////////////////////*/
    
    function getTransferStatus(bytes32 messageHash) 
        external view override returns (TransferStatus memory status) {
        return transferStatuses[messageHash];
    }
    
    function getTransferHistory(address userAddress, uint256 limit, uint256 offset) 
        external view override returns (TransferStatus[] memory transfers) {
        
        bytes32[] memory userTransferHashes = userTransfers[userAddress];
        
        if (offset >= userTransferHashes.length) {
            return new TransferStatus[](0);
        }
        
        uint256 end = offset + limit;
        if (end > userTransferHashes.length) {
            end = userTransferHashes.length;
        }
        
        uint256 resultLength = end - offset;
        transfers = new TransferStatus[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            transfers[i] = transferStatuses[userTransferHashes[offset + i]];
        }
        
        return transfers;
    }
    
    function getPendingTransfers(address userAddress) 
        external view override returns (bytes32[] memory pendingTransfers) {
        return pendingTransfersByUser[userAddress];
    }
    
    /*//////////////////////////////////////////////////////////////
                        DOMAIN MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    function getSupportedDomains() 
        external view override returns (DomainInfo[] memory domainsArray) {
        
        // Count supported domains
        uint256 count = 0;
        for (uint32 i = 0; i < 10; i++) { // Assuming max 10 domains
            if (domains[i].isSupported) {
                count++;
            }
        }
        
        domainsArray = new DomainInfo[](count);
        uint256 index = 0;
        
        for (uint32 i = 0; i < 10; i++) {
            if (domains[i].isSupported) {
                domainsArray[index] = domains[i];
                index++;
            }
        }
        
        return domainsArray;
    }
    
    function getDomainByChainId(uint256 chainId) 
        external view override returns (DomainInfo memory info) {
        uint32 domain = chainIdToDomainMapping[chainId];
        return domains[domain];
    }
    
    function chainIdToDomain(uint256 chainId) 
        external view override returns (uint32 domain) {
        return chainIdToDomainMapping[chainId];
    }
    
    function domainToChainId(uint32 domain) 
        external view override returns (uint256 chainId) {
        return domainToChainIdMapping[domain];
    }
    
    /*//////////////////////////////////////////////////////////////
                        ATTESTATION SERVICES
    //////////////////////////////////////////////////////////////*/
    
    function getAttestation(bytes32 messageHash) 
        external view override returns (bytes memory attestation, bool isReady) {
        
        attestation = attestations[messageHash];
        isReady = attestation.length > 0;
        
        return (attestation, isReady);
    }
    
    function waitForAttestation(bytes32 messageHash, uint256 timeout) 
        external override returns (bytes memory attestation, bool success) {
        
        uint256 startTime = block.timestamp;
        
        // Simplified implementation - in real implementation would poll Circle API
        while (block.timestamp < startTime + timeout) {
            attestation = attestations[messageHash];
            if (attestation.length > 0) {
                return (attestation, true);
            }
            // In real implementation, would have delay/polling mechanism
        }
        
        return (new bytes(0), false);
    }
    
    /*//////////////////////////////////////////////////////////////
                        UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getTransferTimeEstimate(
        uint32 sourceDomain,
        uint32 destinationDomain,
        bool isFastTransfer
    ) external view override returns (uint256 estimatedTime) {
        
        require(domains[sourceDomain].isSupported, "Source domain not supported");
        require(domains[destinationDomain].isSupported, "Destination domain not supported");
        
        if (isFastTransfer && domains[sourceDomain].fastTransferEnabled && domains[destinationDomain].fastTransferEnabled) {
            return FAST_TRANSFER_TIME;
        }
        
        return STANDARD_TRANSFER_TIME;
    }
    
    function getTransferLimits(uint32 sourceDomain, uint32 destinationDomain) 
        external view override returns (uint256 minAmount, uint256 maxAmount, uint256 dailyLimit) {
        
        DomainInfo memory sourceInfo = domains[sourceDomain];
        DomainInfo memory destInfo = domains[destinationDomain];
        
        minAmount = sourceInfo.minTransferAmount > destInfo.minTransferAmount ? 
                   sourceInfo.minTransferAmount : destInfo.minTransferAmount;
        
        maxAmount = sourceInfo.maxTransferAmount < destInfo.maxTransferAmount ? 
                   sourceInfo.maxTransferAmount : destInfo.maxTransferAmount;
        
        dailyLimit = maxAmount; // Simplified - could have separate daily limits
        
        return (minAmount, maxAmount, dailyLimit);
    }
    
    function checkTransferAllowance(address userAddress, uint256 amount) 
        external view override returns (bool hasAllowance, uint256 currentAllowance) {
        
        currentAllowance = IERC20(USDC).allowance(userAddress, address(this));
        hasAllowance = currentAllowance >= amount;
        
        return (hasAllowance, currentAllowance);
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _initializeDomains() internal {
        // Ethereum mainnet
        domains[0] = DomainInfo({
            domain: 0,
            chainId: 1,
            name: "Ethereum",
            tokenMessenger: address(0), // Would be actual TokenMessenger address
            messageTransmitter: address(0), // Would be actual MessageTransmitter address
            isSupported: true,
            fastTransferEnabled: true,
            minTransferAmount: MIN_TRANSFER_AMOUNT,
            maxTransferAmount: MAX_TRANSFER_AMOUNT
        });
        chainIdToDomainMapping[1] = 0;
        domainToChainIdMapping[0] = 1;
        
        // Base
        domains[6] = DomainInfo({
            domain: 6,
            chainId: 8453,
            name: "Base",
            tokenMessenger: address(0),
            messageTransmitter: address(0),
            isSupported: true,
            fastTransferEnabled: true,
            minTransferAmount: MIN_TRANSFER_AMOUNT,
            maxTransferAmount: MAX_TRANSFER_AMOUNT
        });
        chainIdToDomainMapping[8453] = 6;
        domainToChainIdMapping[6] = 8453;
        
        // Arbitrum
        domains[3] = DomainInfo({
            domain: 3,
            chainId: 42161,
            name: "Arbitrum",
            tokenMessenger: address(0),
            messageTransmitter: address(0),
            isSupported: true,
            fastTransferEnabled: true,
            minTransferAmount: MIN_TRANSFER_AMOUNT,
            maxTransferAmount: MAX_TRANSFER_AMOUNT
        });
        chainIdToDomainMapping[42161] = 3;
        domainToChainIdMapping[3] = 42161;
        
        // Initialize fast transfer fees (in basis points)
        fastTransferFees[0][6] = 25; // 0.25% Ethereum to Base
        fastTransferFees[0][3] = 30; // 0.30% Ethereum to Arbitrum
        fastTransferFees[6][0] = 25; // 0.25% Base to Ethereum
        fastTransferFees[6][3] = 35; // 0.35% Base to Arbitrum
        fastTransferFees[3][0] = 30; // 0.30% Arbitrum to Ethereum
        fastTransferFees[3][6] = 35; // 0.35% Arbitrum to Base
    }
    
    function _validateTransferParams(TransferParams calldata params) internal view {
        require(params.sender != address(0), "Invalid sender");
        require(params.recipient != address(0), "Invalid recipient");
        require(params.amount >= MIN_TRANSFER_AMOUNT, "Amount too small");
        require(params.amount <= MAX_TRANSFER_AMOUNT, "Amount too large");
        require(domains[params.destinationDomain].isSupported, "Unsupported destination domain");
        
        // Check USDC allowance
        require(
            IERC20(USDC).allowance(params.sender, address(this)) >= params.amount,
            "Insufficient allowance"
        );
        
        // Check USDC balance
        require(
            IERC20(USDC).balanceOf(params.sender) >= params.amount,
            "Insufficient balance"
        );
    }
    
    function _validateFastTransferParams(FastTransferParams calldata params) internal view {
        require(params.sender != address(0), "Invalid sender");
        require(params.recipient != address(0), "Invalid recipient");
        require(params.amount >= MIN_TRANSFER_AMOUNT, "Amount too small");
        require(params.amount <= MAX_TRANSFER_AMOUNT, "Amount too large");
        require(domains[params.destinationDomain].isSupported, "Unsupported destination domain");
        require(domains[params.destinationDomain].fastTransferEnabled, "Fast transfer not enabled");
        
        // Check USDC allowance and balance
        require(
            IERC20(USDC).allowance(params.sender, address(this)) >= params.amount,
            "Insufficient allowance"
        );
        require(
            IERC20(USDC).balanceOf(params.sender) >= params.amount,
            "Insufficient balance"
        );
    }
    
    function _calculateFastTransferFee(
        uint256 amount, 
        uint32 sourceDomain, 
        uint32 destinationDomain
    ) internal view returns (uint256) {
        uint256 feePercentage = fastTransferFees[sourceDomain][destinationDomain];
        if (feePercentage == 0) {
            feePercentage = 50; // Default 0.5%
        }
        return (amount * feePercentage) / 10000;
    }
    
    function _generateMessageHash() internal returns (bytes32) {
        return keccak256(abi.encodePacked(++messageCounter, block.timestamp, msg.sender));
    }
    
    function _simulateCCTPMessage(bytes32 messageHash, TransferParams calldata params) internal {
        // Simulate Circle attestation service
        // In real implementation, this would be handled by Circle's infrastructure
        bytes memory simulatedAttestation = abi.encodePacked(messageHash, block.timestamp);
        attestations[messageHash] = simulatedAttestation;
        
        emit AttestationReceived(messageHash, keccak256(simulatedAttestation));
    }
    
    function _simulateFastTransfer(
        bytes32 messageHash, 
        FastTransferParams calldata params, 
        uint256 fee
    ) internal {
        // Simulate fast transfer completion
        // In real implementation, this would be handled by fast transfer providers
        
        TransferStatus storage status = transferStatuses[messageHash];
        status.isCompleted = true;
        status.completedTimestamp = block.timestamp;
        
        _removePendingTransfer(params.sender, messageHash);
        
        emit TransferCompleted(messageHash, params.recipient, params.amount - fee);
    }
    
    function _verifyAttestation(bytes32 messageHash, bytes calldata attestation) internal view returns (bool) {
        // Simplified attestation verification
        // In real implementation, would verify Circle's signature
        bytes memory storedAttestation = attestations[messageHash];
        return storedAttestation.length > 0 && keccak256(storedAttestation) == keccak256(attestation);
    }
    
    function _removePendingTransfer(address userAddress, bytes32 messageHash) internal {
        bytes32[] storage pending = pendingTransfersByUser[userAddress];
        
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == messageHash) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                break;
            }
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function configureDomain(
        uint32 domain,
        uint256 chainId,
        string calldata name,
        address tokenMessenger,
        address messageTransmitter,
        bool fastTransferEnabled,
        uint256 minTransferAmount,
        uint256 maxTransferAmount
    ) external onlyOwner {
        domains[domain] = DomainInfo({
            domain: domain,
            chainId: chainId,
            name: name,
            tokenMessenger: tokenMessenger,
            messageTransmitter: messageTransmitter,
            isSupported: true,
            fastTransferEnabled: fastTransferEnabled,
            minTransferAmount: minTransferAmount,
            maxTransferAmount: maxTransferAmount
        });
        
        chainIdToDomainMapping[chainId] = domain;
        domainToChainIdMapping[domain] = chainId;
        
        emit DomainAdded(domain, chainId, name);
        emit DomainConfigured(domain, chainId, fastTransferEnabled);
    }
    
    function setFastTransferFee(
        uint32 sourceDomain,
        uint32 destinationDomain,
        uint256 feePercentage
    ) external onlyOwner {
        require(feePercentage <= MAX_FAST_TRANSFER_FEE, "Fee too high");
        fastTransferFees[sourceDomain][destinationDomain] = feePercentage;
        
        emit FastTransferFeeUpdated(sourceDomain, destinationDomain, feePercentage);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}