// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSTaskHook} from "@eigenlayer/contracts/interfaces/IAVSTaskHook.sol";
import {ITaskMailboxTypes} from "@eigenlayer/contracts/interfaces/ITaskMailbox.sol";
import {IYieldOptimizationTaskHook} from "../interfaces/IYieldOptimizationTaskHook.sol";

/**
 * @title USDCYieldIntelligenceTaskHook
 * @author AVS Yield Labs
 * @notice L2 task hook that interfaces between EigenLayer task system and USDC Yield Optimization Hook
 * @dev This is a CONNECTOR contract that:
 * - Validates task parameters for USDC yield intelligence operations
 * - Calculates fees for different yield monitoring task types
 * - Interfaces with the main USDC Yield Optimization Hook contract
 * - Does NOT contain yield optimization business logic itself
 */
contract USDCYieldIntelligenceTaskHook is IAVSTaskHook, IYieldOptimizationTaskHook {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Address of the main USDC Yield Optimization Hook contract
    address public immutable yieldOptimizationHook;
    
    /// @notice Address of the L1 service manager
    address public immutable serviceManager;
    
    /// @notice Task type constants for USDC yield intelligence operations
    bytes32 public constant TASK_TYPE_YIELD_ATTESTATION = keccak256("YIELD_ATTESTATION");
    bytes32 public constant TASK_TYPE_YIELD_CONSENSUS = keccak256("YIELD_CONSENSUS");
    bytes32 public constant TASK_TYPE_OPPORTUNITY_DETECTION = keccak256("OPPORTUNITY_DETECTION");
    bytes32 public constant TASK_TYPE_RISK_ASSESSMENT = keccak256("RISK_ASSESSMENT");
    bytes32 public constant TASK_TYPE_CROSS_CHAIN_REBALANCE = keccak256("CROSS_CHAIN_REBALANCE");
    bytes32 public constant TASK_TYPE_OPERATOR_SLASHING = keccak256("OPERATOR_SLASHING");
    
    /// @notice Fee structure for different task types (in wei)
    mapping(bytes32 => uint96) public taskTypeFees;
    
    /// @notice Supported USDC yield protocols
    mapping(bytes32 => bool) public supportedProtocols;
    
    /// @notice Supported chain IDs for cross-chain yield farming
    mapping(uint256 => bool) public supportedChains;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event YieldTaskValidated(bytes32 indexed taskHash, bytes32 taskType, address caller);
    event YieldTaskCreated(bytes32 indexed taskHash, bytes32 taskType);
    event YieldTaskResultSubmitted(bytes32 indexed taskHash, address caller);
    event YieldTaskFeeCalculated(bytes32 indexed taskHash, bytes32 taskType, uint96 fee);
    event YieldOptimizationHookUpdated(address indexed oldHook, address indexed newHook);
    event ProtocolSupportUpdated(bytes32 indexed protocolId, bool supported);
    event ChainSupportUpdated(uint256 indexed chainId, bool supported);
    
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyServiceManager() {
        require(msg.sender == serviceManager, "Only service manager can call");
        _;
    }
    
    modifier onlyYieldOptimizationHook() {
        require(msg.sender == yieldOptimizationHook, "Only yield optimization hook");
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @param _yieldOptimizationHook Address of the main USDC Yield Optimization Hook contract
     * @param _serviceManager Address of the L1 service manager
     */
    constructor(address _yieldOptimizationHook, address _serviceManager) {
        require(_yieldOptimizationHook != address(0), "Invalid yield optimization hook");
        require(_serviceManager != address(0), "Invalid service manager");
        
        yieldOptimizationHook = _yieldOptimizationHook;
        serviceManager = _serviceManager;
        
        // Initialize default fees (in wei)
        taskTypeFees[TASK_TYPE_YIELD_ATTESTATION] = 0.0005 ether;        // 0.0005 ETH
        taskTypeFees[TASK_TYPE_YIELD_CONSENSUS] = 0.001 ether;           // 0.001 ETH
        taskTypeFees[TASK_TYPE_OPPORTUNITY_DETECTION] = 0.002 ether;     // 0.002 ETH
        taskTypeFees[TASK_TYPE_RISK_ASSESSMENT] = 0.001 ether;           // 0.001 ETH
        taskTypeFees[TASK_TYPE_CROSS_CHAIN_REBALANCE] = 0.005 ether;     // 0.005 ETH
        taskTypeFees[TASK_TYPE_OPERATOR_SLASHING] = 0.01 ether;          // 0.01 ETH
        
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
                            IAVSTaskHook IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Validate task parameters before task creation for USDC yield intelligence
     * @param caller The address creating the task
     * @param taskParams The task parameters
     */
    function validatePreTaskCreation(
        address caller,
        ITaskMailboxTypes.TaskParams memory taskParams
    ) external view override {
        // Extract task type from payload
        bytes32 taskType = _extractTaskType(taskParams.payload);
        
        // Validate task type is supported
        require(_isValidYieldTaskType(taskType), "Unsupported yield task type");
        
        // Validate caller permissions
        require(caller != address(0), "Invalid caller");
        
        // USDC yield-specific validations based on task type
        if (taskType == TASK_TYPE_YIELD_ATTESTATION) {
            _validateYieldAttestationTask(taskParams.payload);
        } else if (taskType == TASK_TYPE_YIELD_CONSENSUS) {
            _validateYieldConsensusTask(taskParams.payload);
        } else if (taskType == TASK_TYPE_OPPORTUNITY_DETECTION) {
            _validateOpportunityDetectionTask(taskParams.payload);
        } else if (taskType == TASK_TYPE_RISK_ASSESSMENT) {
            _validateRiskAssessmentTask(taskParams.payload);
        } else if (taskType == TASK_TYPE_CROSS_CHAIN_REBALANCE) {
            _validateCrossChainRebalanceTask(taskParams.payload);
        } else if (taskType == TASK_TYPE_OPERATOR_SLASHING) {
            _validateOperatorSlashingTask(taskParams.payload);
        }
        
        emit YieldTaskValidated(keccak256(abi.encode(taskParams)), taskType, caller);
    }
    
    /**
     * @notice Handle post-task creation logic for yield intelligence tasks
     * @param taskHash The hash of the created task
     */
    function handlePostTaskCreation(bytes32 taskHash) external override {
        // Notify the main USDC Yield Optimization Hook about new tasks
        emit YieldTaskCreated(taskHash, bytes32(0)); // Task type would need to be stored/retrieved
    }
    
    /**
     * @notice Validate task result before submission for yield intelligence
     * @param caller The address submitting the result
     * @param taskHash The task hash
     * @param cert The certificate (if any)
     * @param result The task result
     */
    function validatePreTaskResultSubmission(
        address caller,
        bytes32 taskHash,
        bytes memory cert,
        bytes memory result
    ) external view override {
        // Validate caller is authorized
        require(caller != address(0), "Invalid caller");
        
        // Validate result format for yield intelligence
        require(result.length > 0, "Empty result");
        
        // Additional validation logic for yield data integrity
        _validateYieldTaskResult(result);
    }
    
    /**
     * @notice Handle post-task result submission for yield optimization
     * @param caller The address that submitted the result
     * @param taskHash The task hash
     */
    function handlePostTaskResultSubmission(
        address caller,
        bytes32 taskHash
    ) external override {
        // Trigger actions in the main USDC Yield Optimization Hook
        emit YieldTaskResultSubmitted(taskHash, caller);
    }
    
    /**
     * @notice Calculate fee for a yield intelligence task
     * @param taskParams The task parameters
     * @return The calculated fee in wei
     */
    function calculateTaskFee(
        ITaskMailboxTypes.TaskParams memory taskParams
    ) external view override returns (uint96) {
        bytes32 taskType = _extractTaskType(taskParams.payload);
        uint96 baseFee = taskTypeFees[taskType];
        
        // Dynamic fee calculation based on task complexity
        uint96 complexityMultiplier = _calculateComplexityMultiplier(taskParams.payload, taskType);
        
        return baseFee + (baseFee * complexityMultiplier / 10000); // complexityMultiplier in basis points
    }
    
    /*//////////////////////////////////////////////////////////////
                           YIELD-SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Process yield optimization request from hook
     * @param yieldData Encoded yield optimization parameters
     */
    function processYieldOptimization(bytes calldata yieldData) external override onlyYieldOptimizationHook {
        // Decode yield optimization request
        (bytes32 protocolId, uint256 chainId, uint256 amount, uint256 targetYield) = abi.decode(
            yieldData, 
            (bytes32, uint256, uint256, uint256)
        );
        
        require(supportedProtocols[protocolId], "Protocol not supported");
        require(supportedChains[chainId], "Chain not supported");
        require(amount > 0, "Invalid amount");
        require(targetYield > 0, "Invalid target yield");
        
        // Process optimization logic would go here
        // For now, just emit events
        bytes32 opportunityId = keccak256(abi.encodePacked(protocolId, chainId, amount, block.timestamp));
        emit YieldTaskCreated(opportunityId, TASK_TYPE_OPPORTUNITY_DETECTION);
    }
    
    function getYieldOptimizationHook() external view override returns (address) {
        return yieldOptimizationHook;
    }
    
    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Extract task type from payload
     * @param payload The task payload
     * @return The task type hash
     */
    function _extractTaskType(bytes memory payload) internal pure returns (bytes32) {
        if (payload.length < 32) return bytes32(0);
        
        // Assume first 32 bytes contain task type
        bytes32 taskType;
        assembly {
            taskType := mload(add(payload, 32))
        }
        return taskType;
    }
    
    /**
     * @notice Check if task type is valid for yield intelligence
     * @param taskType The task type to check
     * @return Whether the task type is supported
     */
    function _isValidYieldTaskType(bytes32 taskType) internal view returns (bool) {
        return taskType == TASK_TYPE_YIELD_ATTESTATION ||
               taskType == TASK_TYPE_YIELD_CONSENSUS ||
               taskType == TASK_TYPE_OPPORTUNITY_DETECTION ||
               taskType == TASK_TYPE_RISK_ASSESSMENT ||
               taskType == TASK_TYPE_CROSS_CHAIN_REBALANCE ||
               taskType == TASK_TYPE_OPERATOR_SLASHING;
    }
    
    /**
     * @notice Calculate complexity multiplier for dynamic fee calculation
     * @param payload The task payload
     * @param taskType The task type
     * @return multiplier Complexity multiplier in basis points
     */
    function _calculateComplexityMultiplier(bytes memory payload, bytes32 taskType) internal view returns (uint96 multiplier) {
        // Base complexity
        multiplier = 0;
        
        if (taskType == TASK_TYPE_CROSS_CHAIN_REBALANCE) {
            // Cross-chain operations are more complex
            multiplier += 2000; // 20% increase
        }
        
        if (taskType == TASK_TYPE_OPPORTUNITY_DETECTION) {
            // Multiple protocol analysis
            multiplier += 1000; // 10% increase
        }
        
        // Additional complexity based on payload size
        if (payload.length > 256) {
            multiplier += 500; // 5% increase for larger payloads
        }
        
        return multiplier;
    }
    
    /**
     * @notice Validate yield attestation task parameters
     * @param payload The task payload
     */
    function _validateYieldAttestationTask(bytes memory payload) internal view {
        require(payload.length >= 224, "Invalid yield attestation payload"); // protocolId + chainId + yieldRate + tvl + utilization + riskScore + dataHash
        
        // Extract and validate protocol and chain
        (bytes32 protocolId, uint256 chainId, uint256 yieldRate) = abi.decode(payload, (bytes32, uint256, uint256));
        require(supportedProtocols[protocolId], "Protocol not supported");
        require(supportedChains[chainId], "Chain not supported");
        require(yieldRate <= 50000, "Yield rate too high"); // Max 500% APY
    }
    
    /**
     * @notice Validate yield consensus task parameters
     * @param payload The task payload
     */
    function _validateYieldConsensusTask(bytes memory payload) internal pure {
        require(payload.length >= 128, "Invalid yield consensus payload");
        // Additional consensus-specific validations
    }
    
    /**
     * @notice Validate opportunity detection task parameters
     * @param payload The task payload
     */
    function _validateOpportunityDetectionTask(bytes memory payload) internal view {
        require(payload.length >= 96, "Invalid opportunity detection payload");
        
        // Extract protocol and validate
        (bytes32 protocolId, uint256 chainId) = abi.decode(payload, (bytes32, uint256));
        require(supportedProtocols[protocolId], "Protocol not supported");
        require(supportedChains[chainId], "Chain not supported");
    }
    
    /**
     * @notice Validate risk assessment task parameters
     * @param payload The task payload
     */
    function _validateRiskAssessmentTask(bytes memory payload) internal view {
        require(payload.length >= 96, "Invalid risk assessment payload");
        
        // Extract and validate protocol
        (bytes32 protocolId, uint256 chainId) = abi.decode(payload, (bytes32, uint256));
        require(supportedProtocols[protocolId], "Protocol not supported");
        require(supportedChains[chainId], "Chain not supported");
    }
    
    /**
     * @notice Validate cross-chain rebalance task parameters
     * @param payload The task payload
     */
    function _validateCrossChainRebalanceTask(bytes memory payload) internal view {
        require(payload.length >= 160, "Invalid cross-chain rebalance payload");
        
        // Extract and validate chains and amount
        (uint256 fromChain, uint256 toChain, uint256 amount, bytes32 protocolId) = abi.decode(
            payload, (uint256, uint256, uint256, bytes32)
        );
        require(supportedChains[fromChain], "Source chain not supported");
        require(supportedChains[toChain], "Target chain not supported");
        require(fromChain != toChain, "Same chain rebalance");
        require(amount > 0, "Invalid amount");
        require(supportedProtocols[protocolId], "Protocol not supported");
    }
    
    /**
     * @notice Validate operator slashing task parameters
     * @param payload The task payload
     */
    function _validateOperatorSlashingTask(bytes memory payload) internal pure {
        require(payload.length >= 160, "Invalid operator slashing payload");
        // Additional slashing-specific validations
    }
    
    /**
     * @notice Validate yield task result data
     * @param result The task result data
     */
    function _validateYieldTaskResult(bytes memory result) internal pure {
        require(result.length >= 32, "Result too short");
        // Additional result validation logic
    }
    
    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get fee for a specific task type
     * @param taskType The task type
     * @return The fee for that task type
     */
    function getTaskTypeFee(bytes32 taskType) external view returns (uint96) {
        return taskTypeFees[taskType];
    }
    
    /**
     * @notice Get all supported yield task types
     * @return Array of supported task type hashes
     */
    function getSupportedYieldTaskTypes() external pure returns (bytes32[] memory) {
        bytes32[] memory types = new bytes32[](6);
        types[0] = TASK_TYPE_YIELD_ATTESTATION;
        types[1] = TASK_TYPE_YIELD_CONSENSUS;
        types[2] = TASK_TYPE_OPPORTUNITY_DETECTION;
        types[3] = TASK_TYPE_RISK_ASSESSMENT;
        types[4] = TASK_TYPE_CROSS_CHAIN_REBALANCE;
        types[5] = TASK_TYPE_OPERATOR_SLASHING;
        return types;
    }
    
    /**
     * @notice Check if a protocol is supported
     * @param protocolId The protocol identifier
     * @return Whether the protocol is supported
     */
    function isProtocolSupported(bytes32 protocolId) external view returns (bool) {
        return supportedProtocols[protocolId];
    }
    
    /**
     * @notice Check if a chain is supported
     * @param chainId The chain identifier
     * @return Whether the chain is supported
     */
    function isChainSupported(uint256 chainId) external view returns (bool) {
        return supportedChains[chainId];
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update fee for a task type (only service manager)
     * @param taskType The task type to update
     * @param newFee The new fee amount
     */
    function updateTaskTypeFee(bytes32 taskType, uint96 newFee) external onlyServiceManager {
        require(_isValidYieldTaskType(taskType), "Invalid task type");
        taskTypeFees[taskType] = newFee;
    }
    
    /**
     * @notice Update protocol support status (only service manager)
     * @param protocolId The protocol identifier
     * @param supported Whether the protocol should be supported
     */
    function updateProtocolSupport(bytes32 protocolId, bool supported) external onlyServiceManager {
        supportedProtocols[protocolId] = supported;
        emit ProtocolSupportUpdated(protocolId, supported);
    }
    
    /**
     * @notice Update chain support status (only service manager)
     * @param chainId The chain identifier
     * @param supported Whether the chain should be supported
     */
    function updateChainSupport(uint256 chainId, bool supported) external onlyServiceManager {
        supportedChains[chainId] = supported;
        emit ChainSupportUpdated(chainId, supported);
    }
}