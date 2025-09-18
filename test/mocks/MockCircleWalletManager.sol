// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../src/interfaces/ICircleWalletManager.sol";

/**
 * @title MockCircleWalletManager
 * @notice Mock implementation of Circle Wallet Manager for testing
 */
contract MockCircleWalletManager is ICircleWalletManager {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    mapping(address => WalletConfig) private userWallets;
    mapping(bytes32 => ExecutionResult) private executionResults;
    mapping(address => bool) private automationEnabled;
    mapping(address => uint256) private nextRebalanceTime;
    
    // Test state tracking
    bool private shouldFailRebalancing = false;
    bool private rebalanceExecuted = false;
    uint256 private rebalanceCount = 0;
    bytes32 private lastRebalanceProtocol;
    
    /*//////////////////////////////////////////////////////////////
                        WALLET MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    function setupUserWallet(address userAddress, WalletConfig calldata config)
        external override returns (address walletAddress)
    {
        userWallets[userAddress] = config;
        walletAddress = config.walletAddress;
        
        emit WalletCreated(userAddress, walletAddress);
        emit WalletConfigured(userAddress, config);
    }
    
    function getUserWalletConfig(address userAddress)
        external view override returns (WalletConfig memory)
    {
        return userWallets[userAddress];
    }
    
    function updateWalletConfig(address userAddress, WalletConfig calldata newConfig)
        external override
    {
        userWallets[userAddress] = newConfig;
        emit WalletConfigured(userAddress, newConfig);
    }
    
    function hasUserWallet(address userAddress)
        external view override returns (bool hasWallet, address walletAddress)
    {
        hasWallet = userWallets[userAddress].walletAddress != address(0);
        walletAddress = userWallets[userAddress].walletAddress;
    }
    
    /*//////////////////////////////////////////////////////////////
                        REBALANCING EXECUTION
    //////////////////////////////////////////////////////////////*/
    
    function executeRebalancing(RebalanceRequest calldata request)
        external override returns (bytes32 requestId)
    {
        if (shouldFailRebalancing) {
            revert("Mock rebalancing failure");
        }
        
        requestId = keccak256(abi.encodePacked(request.userAddress, block.timestamp));
        rebalanceExecuted = true;
        rebalanceCount++;
        lastRebalanceProtocol = request.toProtocol;
        
        // Mock successful execution
        executionResults[requestId] = ExecutionResult({
            requestId: requestId,
            success: true,
            amountExecuted: request.amount,
            gasUsed: 150000, // Mock gas usage
            feesPaid: request.amount / 1000, // 0.1% fee
            transactionHash: keccak256(abi.encodePacked("tx", requestId)),
            errorMessage: ""
        });
        
        emit RebalancingExecuted(
            requestId,
            request.userAddress,
            request.fromProtocol,
            request.toProtocol,
            request.amount
        );
        
        return requestId;
    }
    
    function executeBatchRebalancing(RebalanceRequest[] calldata requests)
        external override returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](requests.length);
        
        for (uint256 i = 0; i < requests.length; i++) {
            requestIds[i] = this.executeRebalancing(requests[i]);
        }
    }
    
    function getExecutionResult(bytes32 requestId)
        external view override returns (ExecutionResult memory)
    {
        return executionResults[requestId];
    }
    
    function cancelRebalancing(bytes32 requestId)
        external override returns (bool success)
    {
        // Mock cancellation
        executionResults[requestId].success = false;
        executionResults[requestId].errorMessage = "Cancelled by user";
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
    ) external override returns (bool success, bytes32 transactionHash) {
        success = !shouldFailRebalancing;
        transactionHash = keccak256(abi.encodePacked("deposit", userAddress, protocolId, amount));
    }
    
    function withdrawFromProtocol(
        address userAddress,
        bytes32 protocolId,
        uint256 amount,
        uint256 chainId
    ) external override returns (bool success, bytes32 transactionHash) {
        success = !shouldFailRebalancing;
        transactionHash = keccak256(abi.encodePacked("withdraw", userAddress, protocolId, amount));
    }
    
    function getUserUSDCBalance(address userAddress)
        external view override returns (
            uint256 totalBalance,
            bytes32[] memory protocolIds,
            uint256[] memory protocolAmounts,
            uint256[] memory chainIds,
            uint256[] memory chainAmounts
        )
    {
        // Mock implementation
        totalBalance = 100000e6; // Mock 100k USDC balance
        
        // Mock protocol balances
        protocolIds = new bytes32[](2);
        protocolAmounts = new uint256[](2);
        protocolIds[0] = keccak256("aave");
        protocolAmounts[0] = 50000e6;
        protocolIds[1] = keccak256("compound");
        protocolAmounts[1] = 50000e6;
        
        // Mock chain balances
        chainIds = new uint256[](2);
        chainAmounts = new uint256[](2);
        chainIds[0] = 1; // Ethereum mainnet
        chainAmounts[0] = 60000e6;
        chainIds[1] = 137; // Polygon
        chainAmounts[1] = 40000e6;
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
    ) external override returns (bool success, bytes32 transferId) {
        success = !shouldFailRebalancing;
        transferId = keccak256(abi.encodePacked("transfer", userAddress, amount, toChainId));
        
        if (success) {
            emit CrossChainTransferInitiated(
                transferId,
                userAddress,
                amount,
                fromChainId,
                toChainId
            );
        }
    }
    
    function getCrossChainTransferStatus(bytes32 transferId)
        external view override returns (
            string memory status,
            uint256 completedTimestamp,
            string memory failureReason
        )
    {
        status = "completed";
        completedTimestamp = block.timestamp;
        failureReason = "";
    }
    
    /*//////////////////////////////////////////////////////////////
                        AUTOMATION & SCHEDULING
    //////////////////////////////////////////////////////////////*/
    
    function setupAutomatedRebalancing(
        address userAddress,
        uint256 frequency,
        uint256 threshold,
        uint256 maxAmount
    ) external override {
        automationEnabled[userAddress] = true;
        nextRebalanceTime[userAddress] = block.timestamp + frequency;
        
        emit AutomatedRebalancingEnabled(userAddress, frequency, threshold);
    }
    
    function disableAutomatedRebalancing(address userAddress) external override {
        automationEnabled[userAddress] = false;
        emit AutomatedRebalancingDisabled(userAddress);
    }
    
    function getAutomationStatus(address userAddress)
        external view override returns (bool isEnabled, uint256 nextRebalanceTimeValue)
    {
        isEnabled = automationEnabled[userAddress];
        nextRebalanceTimeValue = nextRebalanceTime[userAddress];
    }
    
    /*//////////////////////////////////////////////////////////////
                            GAS & FEES
    //////////////////////////////////////////////////////////////*/
    
    function enableUSDCGasPayments(address userAddress, uint256 maxGasPerTransaction)
        external override
    {
        emit USDCGasPaymentEnabled(userAddress, maxGasPerTransaction);
    }
    
    function estimateRebalancingCost(RebalanceRequest calldata request)
        external pure override returns (uint256 estimatedGasCost, uint256 confidence)
    {
        // Mock gas estimation
        estimatedGasCost = 50e6; // 50 USDC
        confidence = 9000; // 90% confidence
    }
    
    /*//////////////////////////////////////////////////////////////
                        MOCK HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function setShouldFailRebalancing(bool shouldFail) external {
        shouldFailRebalancing = shouldFail;
    }
    
    function wasRebalanceExecuted() external view returns (bool) {
        return rebalanceExecuted;
    }
    
    function getRebalanceCount() external view returns (uint256) {
        return rebalanceCount;
    }
    
    function getLastRebalanceProtocol() external view returns (bytes32) {
        return lastRebalanceProtocol;
    }
    
    function resetMockState() external {
        shouldFailRebalancing = false;
        rebalanceExecuted = false;
        rebalanceCount = 0;
        lastRebalanceProtocol = bytes32(0);
    }
}