// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IYieldIntelligenceServiceManager
 * @notice Interface for USDC Yield Intelligence Service Manager
 */
interface IYieldIntelligenceServiceManager {
    /**
     * @notice Register an operator specifically for USDC yield intelligence tasks
     * @param operator The operator address to register
     * @param operatorSignature The operator's signature for EigenLayer
     */
    function registerYieldIntelligenceOperator(
        address operator,
        bytes calldata operatorSignature
    ) external payable;

    /**
     * @notice Deregister an operator from USDC yield intelligence tasks
     * @param operator The operator address to deregister
     */
    function deregisterYieldIntelligenceOperator(address operator) external;

    /**
     * @notice Check if an operator meets USDC yield intelligence requirements
     * @param operator The operator address to check
     * @return Whether the operator is qualified for yield intelligence operations
     */
    function isYieldIntelligenceOperatorQualified(address operator) external view returns (bool);

    /**
     * @notice Get the L2 USDC Yield Hook contract address
     * @return The address of the main USDC yield optimization logic contract
     */
    function getYieldOptimizationHook() external view returns (address);

    /**
     * @notice Process yield optimization data from the main USDC Yield Hook
     * @param yieldData The yield opportunity data
     */
    function processYieldOptimization(bytes calldata yieldData) external;

    /**
     * @notice Events
     */
    event YieldIntelligenceOperatorRegistered(address indexed operator, bytes32 indexed operatorId);
    event YieldIntelligenceOperatorDeregistered(address indexed operator, bytes32 indexed operatorId);
    event YieldOptimizationHookUpdated(address indexed oldHook, address indexed newHook);
    event YieldOptimizationProcessed(bytes32 indexed yieldOpportunityId, address indexed operator);
}
