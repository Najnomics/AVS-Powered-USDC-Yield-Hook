// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAVSTaskHook} from "@eigenlayer-contracts/src/contracts/interfaces/IAVSTaskHook.sol";
import {ITaskMailboxTypes} from "@eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";

/**
 * @title IYieldOptimizationTaskHook
 * @notice Interface for USDC Yield Optimization Task Hook
 */
interface IYieldOptimizationTaskHook is IAVSTaskHook {
    /**
     * @notice Get the main USDC Yield Optimization Hook address
     * @return The address of the main USDC yield optimization logic contract
     */
    function getYieldOptimizationHook() external view returns (address);

    /**
     * @notice Get fee for a specific task type
     * @param taskType The task type
     * @return The fee for that task type
     */
    function getTaskTypeFee(bytes32 taskType) external view returns (uint96);

    /**
     * @notice Get all supported task types
     * @return Array of supported task type hashes
     */
    function getSupportedTaskTypes() external pure returns (bytes32[] memory);

    /**
     * @notice Update fee for a task type (only service manager)
     * @param taskType The task type to update
     * @param newFee The new fee amount
     */
    function updateTaskTypeFee(bytes32 taskType, uint96 newFee) external;

    /**
     * @notice Task type constants
     */
    function TASK_TYPE_YIELD_MONITORING() external pure returns (bytes32);
    function TASK_TYPE_CROSS_CHAIN_YIELD_CHECK() external pure returns (bytes32);
    function TASK_TYPE_REBALANCE_EXECUTION() external pure returns (bytes32);
    function TASK_TYPE_RISK_ASSESSMENT() external pure returns (bytes32);

    /**
     * @notice Events
     */
    event TaskValidated(bytes32 indexed taskHash, bytes32 taskType, address caller);
    event TaskCreated(bytes32 indexed taskHash, bytes32 taskType);
    event TaskResultSubmitted(bytes32 indexed taskHash, address caller);
    event TaskFeeCalculated(bytes32 indexed taskHash, bytes32 taskType, uint96 fee);
    event YieldOptimizationHookUpdated(address indexed oldHook, address indexed newHook);
}
