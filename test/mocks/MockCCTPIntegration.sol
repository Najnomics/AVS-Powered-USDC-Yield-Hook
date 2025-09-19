// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../src/interfaces/ICCTPIntegration.sol";

/**
 * @title MockCCTPIntegration
 * @notice Mock implementation of Circle's CCTP integration for testing
 */
contract MockCCTPIntegration is ICCTPIntegration {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    mapping(bytes32 => TransferStatus) private transferStatuses;
    mapping(uint32 => DomainInfo) private domainInfo;
    mapping(address => bytes32[]) private userTransfers;
    mapping(bytes32 => bytes) private attestations;
    
    // Test state tracking
    bool private transferInitiated = false;
    uint256 private lastTransferDestination;
    uint256 private transferCount = 0;
    
    uint32[] private supportedDomains;
    
    constructor() {
        _setupDefaultDomains();
    }
    
    /*//////////////////////////////////////////////////////////////
                        STANDARD TRANSFERS
    //////////////////////////////////////////////////////////////*/
    
    function initiateTransfer(TransferParams calldata params)
        external override returns (bytes32 messageHash)
    {
        messageHash = keccak256(abi.encodePacked(
            params.sender,
            params.recipient,
            params.amount,
            params.destinationDomain,
            block.timestamp
        ));
        
        transferStatuses[messageHash] = TransferStatus({
            messageHash: messageHash,
            timestamp: block.timestamp,
            sourceDomain: _getCurrentDomain(),
            destinationDomain: params.destinationDomain,
            amount: params.amount,
            sender: params.sender,
            recipient: params.recipient,
            isCompleted: false,
            isFastTransfer: false,
            completedTimestamp: 0,
            attestation: bytes32(0)
        });
        
        userTransfers[params.sender].push(messageHash);
        transferInitiated = true;
        transferCount++;
        lastTransferDestination = domainToChainId(params.destinationDomain);
        
        emit TransferInitiated(
            messageHash,
            params.sender,
            params.recipient,
            params.amount,
            _getCurrentDomain(),
            params.destinationDomain
        );
    }
    
    function transferAndExecute(
        TransferParams calldata params,
        address targetContract,
        bytes calldata targetCalldata
    ) external override returns (bytes32 messageHash) {
        messageHash = this.initiateTransfer(params);
        
        // Mock automatic execution on destination
        transferStatuses[messageHash].isCompleted = true;
        transferStatuses[messageHash].completedTimestamp = block.timestamp + 300; // 5 minutes
    }
    
    function completeTransfer(bytes calldata message, bytes calldata attestation)
        external override returns (bool success)
    {
        bytes32 messageHash = keccak256(message);
        
        if (transferStatuses[messageHash].messageHash != bytes32(0)) {
            transferStatuses[messageHash].isCompleted = true;
            transferStatuses[messageHash].completedTimestamp = block.timestamp;
            transferStatuses[messageHash].attestation = keccak256(attestation);
            
            emit TransferCompleted(
                messageHash,
                transferStatuses[messageHash].recipient,
                transferStatuses[messageHash].amount
            );
            
            success = true;
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        FAST TRANSFERS
    //////////////////////////////////////////////////////////////*/
    
    function initiateFastTransfer(FastTransferParams calldata params)
        external override returns (bytes32 messageHash)
    {
        messageHash = keccak256(abi.encodePacked(
            params.sender,
            params.recipient,
            params.amount,
            params.destinationDomain,
            "fast",
            block.timestamp
        ));
        
        uint256 fee = _calculateFastTransferFee(params.amount, params.destinationDomain);
        require(fee <= params.maxFee, "Fee exceeds maximum");
        
        transferStatuses[messageHash] = TransferStatus({
            messageHash: messageHash,
            timestamp: block.timestamp,
            sourceDomain: _getCurrentDomain(),
            destinationDomain: params.destinationDomain,
            amount: params.amount,
            sender: params.sender,
            recipient: params.recipient,
            isCompleted: true, // Fast transfers complete immediately in mock
            isFastTransfer: true,
            completedTimestamp: block.timestamp + 30, // 30 seconds
            attestation: keccak256("fast_attestation")
        });
        
        userTransfers[params.sender].push(messageHash);
        transferInitiated = true;
        transferCount++;
        lastTransferDestination = domainToChainId(params.destinationDomain);
        
        emit FastTransferInitiated(
            messageHash,
            params.sender,
            params.recipient,
            params.amount,
            _getCurrentDomain(),
            params.destinationDomain,
            fee
        );
    }
    
    function getFastTransferFee(uint256 amount, uint32 destinationDomain)
        external pure override returns (uint256 fee, uint256 maxFee)
    {
        fee = amount / 1000; // 0.1% fee
        maxFee = amount / 500; // 0.2% max fee
    }
    
    function isFastTransferAvailable(uint32 sourceDomain, uint32 destinationDomain)
        external pure override returns (bool isAvailable, uint256 estimatedTime)
    {
        isAvailable = true; // Always available in mock
        estimatedTime = 30; // 30 seconds
    }
    
    /*//////////////////////////////////////////////////////////////
                        YIELD OPTIMIZATION HOOKS
    //////////////////////////////////////////////////////////////*/
    
    function transferAndOptimizeYield(
        TransferParams calldata params,
        bytes32 yieldProtocol,
        bytes calldata optimizationData
    ) external override returns (bytes32 messageHash) {
        messageHash = this.transferAndExecute(params, address(0), optimizationData);
        
        emit YieldOptimizationExecuted(
            messageHash,
            params.recipient,
            yieldProtocol,
            params.amount
        );
    }
    
    function fastTransferAndOptimizeYield(
        FastTransferParams calldata params,
        bytes32 yieldProtocol,
        bytes calldata optimizationData
    ) external override returns (bytes32 messageHash) {
        messageHash = this.initiateFastTransfer(params);
        
        emit YieldOptimizationExecuted(
            messageHash,
            params.recipient,
            yieldProtocol,
            params.amount
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                        TRANSFER TRACKING
    //////////////////////////////////////////////////////////////*/
    
    function getTransferStatus(bytes32 messageHash)
        external view override returns (TransferStatus memory)
    {
        return transferStatuses[messageHash];
    }
    
    function getTransferHistory(address userAddress, uint256 limit, uint256 offset)
        external view override returns (TransferStatus[] memory transfers)
    {
        bytes32[] memory userHashes = userTransfers[userAddress];
        uint256 start = offset;
        uint256 end = start + limit;
        
        if (end > userHashes.length) {
            end = userHashes.length;
        }
        
        if (start >= userHashes.length) {
            return new TransferStatus[](0);
        }
        
        transfers = new TransferStatus[](end - start);
        for (uint256 i = start; i < end; i++) {
            transfers[i - start] = transferStatuses[userHashes[i]];
        }
    }
    
    function getPendingTransfers(address userAddress)
        external view override returns (bytes32[] memory pendingTransfers)
    {
        bytes32[] memory userHashes = userTransfers[userAddress];
        uint256 pendingCount = 0;
        
        // Count pending transfers
        for (uint256 i = 0; i < userHashes.length; i++) {
            if (!transferStatuses[userHashes[i]].isCompleted) {
                pendingCount++;
            }
        }
        
        // Collect pending transfers
        pendingTransfers = new bytes32[](pendingCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < userHashes.length; i++) {
            if (!transferStatuses[userHashes[i]].isCompleted) {
                pendingTransfers[index] = userHashes[i];
                index++;
            }
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        DOMAIN MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    function getSupportedDomains()
        external view override returns (DomainInfo[] memory domains)
    {
        domains = new DomainInfo[](supportedDomains.length);
        for (uint256 i = 0; i < supportedDomains.length; i++) {
            domains[i] = domainInfo[supportedDomains[i]];
        }
    }
    
    function getDomainByChainId(uint256 chainId)
        external view override returns (DomainInfo memory info)
    {
        uint32 domain = chainIdToDomain(chainId);
        return domainInfo[domain];
    }
    
    function chainIdToDomain(uint256 chainId)
        public pure override returns (uint32 domain)
    {
        if (chainId == 1) domain = 0;          // Ethereum
        else if (chainId == 8453) domain = 6; // Base
        else if (chainId == 42161) domain = 3; // Arbitrum
        else if (chainId == 137) domain = 7;   // Polygon
        else if (chainId == 31337) domain = 0; // Test network (treat as Ethereum)
        else revert UnsupportedDomain();
    }
    
    function domainToChainId(uint32 domain)
        public pure override returns (uint256 chainId)
    {
        if (domain == 0) chainId = 1;          // Ethereum (also covers test network 31337)
        else if (domain == 6) chainId = 8453;  // Base
        else if (domain == 3) chainId = 42161; // Arbitrum
        else if (domain == 7) chainId = 137;   // Polygon
        else revert UnsupportedDomain();
    }
    
    /*//////////////////////////////////////////////////////////////
                        ATTESTATION SERVICES
    //////////////////////////////////////////////////////////////*/
    
    function getAttestation(bytes32 messageHash)
        external view override returns (bytes memory attestation, bool isReady)
    {
        attestation = attestations[messageHash];
        isReady = attestation.length > 0;
        
        if (!isReady && transferStatuses[messageHash].isCompleted) {
            // Generate mock attestation
            attestation = abi.encodePacked("mock_attestation_", messageHash);
            isReady = true;
        }
    }
    
    function waitForAttestation(bytes32 messageHash, uint256 timeout)
        external override returns (bytes memory attestation, bool success)
    {
        // Mock implementation - always succeeds immediately
        (attestation, success) = this.getAttestation(messageHash);
        
        if (success) {
            emit AttestationReceived(messageHash, keccak256(attestation));
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getTransferTimeEstimate(
        uint32 sourceDomain,
        uint32 destinationDomain,
        bool isFastTransfer
    ) external pure override returns (uint256 estimatedTime) {
        if (isFastTransfer) {
            estimatedTime = 30; // 30 seconds
        } else {
            estimatedTime = 900; // 15 minutes
        }
    }
    
    function getTransferLimits(uint32 sourceDomain, uint32 destinationDomain)
        external pure override returns (uint256 minAmount, uint256 maxAmount, uint256 dailyLimit)
    {
        minAmount = 1e6;      // 1 USDC
        maxAmount = 1000000e6; // 1M USDC
        dailyLimit = 10000000e6; // 10M USDC
    }
    
    function checkTransferAllowance(address userAddress, uint256 amount)
        external pure override returns (bool hasAllowance, uint256 currentAllowance)
    {
        hasAllowance = true;
        currentAllowance = type(uint256).max; // Unlimited for mock
    }
    
    /*//////////////////////////////////////////////////////////////
                        PRIVATE HELPERS
    //////////////////////////////////////////////////////////////*/
    
    function _setupDefaultDomains() private {
        // Ethereum
        domainInfo[0] = DomainInfo({
            domain: 0,
            chainId: 1,
            name: "Ethereum",
            tokenMessenger: address(0x1001),
            messageTransmitter: address(0x1002),
            isSupported: true,
            fastTransferEnabled: true,
            minTransferAmount: 1e6,
            maxTransferAmount: 1000000e6
        });
        supportedDomains.push(0);
        
        // Base
        domainInfo[6] = DomainInfo({
            domain: 6,
            chainId: 8453,
            name: "Base",
            tokenMessenger: address(0x6001),
            messageTransmitter: address(0x6002),
            isSupported: true,
            fastTransferEnabled: true,
            minTransferAmount: 1e6,
            maxTransferAmount: 1000000e6
        });
        supportedDomains.push(6);
        
        // Arbitrum
        domainInfo[3] = DomainInfo({
            domain: 3,
            chainId: 42161,
            name: "Arbitrum",
            tokenMessenger: address(0x3001),
            messageTransmitter: address(0x3002),
            isSupported: true,
            fastTransferEnabled: false,
            minTransferAmount: 1e6,
            maxTransferAmount: 1000000e6
        });
        supportedDomains.push(3);
    }
    
    function _getCurrentDomain() private view returns (uint32) {
        return chainIdToDomain(block.chainid);
    }
    
    function _calculateFastTransferFee(uint256 amount, uint32 destinationDomain)
        private pure returns (uint256)
    {
        return amount / 1000; // 0.1% fee
    }
    
    /*//////////////////////////////////////////////////////////////
                        MOCK HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function wasTransferInitiated() external view returns (bool) {
        return transferInitiated;
    }
    
    function getLastTransferDestination() external view returns (uint256) {
        return lastTransferDestination;
    }
    
    function getTransferCount() external view returns (uint256) {
        return transferCount;
    }
    
    function resetMockState() external {
        transferInitiated = false;
        lastTransferDestination = 0;
        transferCount = 0;
    }
}