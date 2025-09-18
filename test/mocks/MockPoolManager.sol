// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";

/**
 * @title MockPoolManager
 * @notice Mock PoolManager for testing
 */
contract MockPoolManager is IPoolManager {
    
    mapping(PoolId => PoolKey) public pools;
    
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) 
        external pure override returns (int24 tick) {
        // Mock implementation
        return 0;
    }
    
    function modifyLiquidity(
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external pure override returns (BalanceDelta callerDelta, BalanceDelta feesAccrued) {
        // Mock implementation
        return (BalanceDelta.wrap(0), BalanceDelta.wrap(0));
    }
    
    function swap(
        PoolKey memory key,
        SwapParams memory params,
        bytes calldata hookData
    ) external pure override returns (BalanceDelta swapDelta) {
        // Mock implementation
        return BalanceDelta.wrap(0);
    }
    
    function donate(
        PoolKey memory key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external pure override returns (BalanceDelta delta) {
        // Mock implementation
        return BalanceDelta.wrap(0);
    }
    
    function sync(Currency currency) external pure override {
        // Mock implementation
    }
    
    function take(Currency currency, address to, uint256 amount) external pure override {
        // Mock implementation
    }
    
    function settle() external payable override returns (uint256 paid) {
        // Mock implementation
        return 0;
    }
    
    function settleFor(address recipient) external payable override returns (uint256 paid) {
        // Mock implementation
        return 0;
    }
    
    function clear(Currency currency, uint256 amount) external pure override {
        // Mock implementation
    }
    
    function mint(address to, uint256 id, uint256 amount) external pure override {
        // Mock implementation
    }
    
    function burn(address from, uint256 id, uint256 amount) external pure override {
        // Mock implementation
    }
    
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external pure override {
        // Mock implementation
    }
    
    function extsload(bytes32 slot) external view override returns (bytes32 value) {
        // Mock implementation
        return bytes32(0);
    }
    
    function extsload(bytes32 startSlot, uint256 nSlots) 
        external view override returns (bytes32[] memory values) {
        // Mock implementation
        values = new bytes32[](nSlots);
    }
    
    function extsload(bytes32[] calldata slots) 
        external view override returns (bytes32[] memory values) {
        // Mock implementation
        values = new bytes32[](slots.length);
    }
    
    function exttload(bytes32 slot) external view override returns (bytes32 value) {
        // Mock implementation
        return bytes32(0);
    }
    
    function exttload(bytes32[] calldata slots) 
        external view override returns (bytes32[] memory values) {
        // Mock implementation
        values = new bytes32[](slots.length);
    }
    
    // IERC6909Claims functions
    function balanceOf(address owner, uint256 id) external view override returns (uint256 amount) {
        return 0;
    }
    
    function allowance(address owner, address spender, uint256 id) external view override returns (uint256 amount) {
        return 0;
    }
    
    function isOperator(address owner, address spender) external view override returns (bool approved) {
        return false;
    }
    
    function setOperator(address operator, bool approved) external override returns (bool) {
        return true;
    }
    
    function approve(address spender, uint256 id, uint256 amount) external override returns (bool) {
        return true;
    }
    
    function transfer(address receiver, uint256 id, uint256 amount) external override returns (bool) {
        return true;
    }
    
    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) external override returns (bool) {
        return true;
    }
    
    // IProtocolFees functions
    function protocolFeesAccrued(Currency currency) external view override returns (uint256 amount) {
        return 0;
    }
    
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external override {
        // Mock implementation
    }
    
    function setProtocolFeeController(address controller) external override {
        // Mock implementation
    }
    
    function collectProtocolFees(address recipient, Currency currency, uint256 amount) external override returns (uint256 amountCollected) {
        return 0;
    }
    
    function protocolFeeController() external view override returns (address) {
        return address(0);
    }
    
    // IPoolManager functions
    function unlock(bytes calldata data) external override returns (bytes memory) {
        return new bytes(0);
    }
    
    // Additional functions for testing
    function setHook(address hook) external {
        // Mock implementation for testing
    }
}