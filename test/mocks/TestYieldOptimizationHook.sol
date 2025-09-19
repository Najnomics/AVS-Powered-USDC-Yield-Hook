// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {YieldOptimizationHook} from "../../src/hooks/YieldOptimizationHook.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/utils/BaseHook.sol";
import {IYieldIntelligenceAVS} from "../../src/interfaces/IYieldIntelligenceAVS.sol";
import {ICircleWalletManager} from "../../src/interfaces/ICircleWalletManager.sol";
import {ICCTPIntegration} from "../../src/interfaces/ICCTPIntegration.sol";

/**
 * @title TestYieldOptimizationHook
 * @notice Test version of YieldOptimizationHook that skips address validation
 * @dev This allows us to test the hook without needing a valid hook address
 */
contract TestYieldOptimizationHook is YieldOptimizationHook {
    constructor(
        IPoolManager _poolManager,
        IYieldIntelligenceAVS _yieldIntelligenceAVS,
        ICircleWalletManager _circleWalletManager,
        ICCTPIntegration _cctpIntegration,
        address _treasury
    ) YieldOptimizationHook(_poolManager, _yieldIntelligenceAVS, _circleWalletManager, _cctpIntegration, _treasury) {}
    
    /// @dev Override to skip address validation in tests
    function validateHookAddress(BaseHook _this) internal pure override {
        // Skip validation for testing
    }
}
