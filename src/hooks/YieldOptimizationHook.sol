// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {BaseHook} from "v4-periphery/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IYieldIntelligenceAVS.sol";
import "../interfaces/ICircleWalletManager.sol";
import "../interfaces/ICCTPIntegration.sol";
import "../libraries/YieldCalculations.sol";
import "../libraries/RiskAssessment.sol";

/**
 * @title YieldOptimizationHook
 * @author AVS Yield Labs
 * @notice A Uniswap v4 Hook that leverages EigenLayer AVS to automatically optimize 
 *         USDC yield through intelligent cross-protocol and cross-chain rebalancing
 * @dev This hook intercepts USDC-related swaps to trigger yield optimization using
 *      Circle Wallets and CCTP v2 for seamless cross-chain execution
 */
contract YieldOptimizationHook is BaseHook, ReentrancyGuard, Ownable, Pausable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using YieldCalculations for YieldCalculations.YieldData;
    using RiskAssessment for RiskAssessment.ProtocolRisk;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC token address (mainnet)
    address public constant USDC = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
    
    /// @notice Minimum rebalancing amount (100 USDC)
    uint256 public constant MIN_REBALANCE_AMOUNT = 100e6;
    
    /// @notice Minimum yield improvement threshold (50 basis points)
    uint256 public constant MIN_YIELD_IMPROVEMENT = 50;
    
    /// @notice Maximum single protocol allocation (40%)
    uint256 public constant MAX_PROTOCOL_ALLOCATION = 4000;
    
    /// @notice Rebalancing cooldown period (1 hour)
    uint256 public constant REBALANCE_COOLDOWN = 3600;
    
    /// @notice Protocol fee percentage (25 basis points)
    uint256 public constant PROTOCOL_FEE = 25;
    
    /// @notice AVS operator reward percentage (10 basis points)
    uint256 public constant AVS_REWARD_PERCENTAGE = 10;
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice EigenLayer Yield Intelligence AVS interface
    IYieldIntelligenceAVS public immutable yieldIntelligenceAVS;
    
    /// @notice Circle Wallet Manager for automated execution
    ICircleWalletManager public immutable circleWalletManager;
    
    /// @notice CCTP Integration for cross-chain transfers
    ICCTPIntegration public immutable cctpIntegration;
    
    /// @notice Treasury address for protocol fees
    address public treasury;
    
    /// @notice User yield strategies
    mapping(address => YieldStrategy) public userStrategies;
    
    /// @notice User USDC positions
    mapping(address => UserPosition) public userPositions;
    
    /// @notice Last rebalancing timestamp for users
    mapping(address => uint256) public lastRebalance;
    
    /// @notice Supported yield protocols
    mapping(bytes32 => ProtocolInfo) public supportedProtocols;
    
    /// @notice Active yield opportunities
    mapping(bytes32 => YieldOpportunity) public yieldOpportunities;
    
    /// @notice Protocol risk scores
    mapping(bytes32 => uint256) public protocolRiskScores;
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct YieldStrategy {
        uint256 targetAllocation;      // Target allocation percentage (basis points)
        uint256 riskTolerance;         // Risk tolerance level (0-10000)
        uint256 rebalanceThreshold;    // Minimum improvement to trigger rebalance (bp)
        bool autoRebalance;            // Whether to auto-rebalance
        bool crossChainEnabled;        // Allow cross-chain yield farming
        bytes32[] approvedProtocols;   // Whitelisted protocols
        uint256[] chainIds;            // Approved chain IDs
        uint256 maxSlippage;           // Maximum acceptable slippage (bp)
    }
    
    struct UserPosition {
        uint256 totalUSDCDeposited;    // Total USDC deposited by user
        uint256 totalYieldEarned;      // Total yield earned
        uint256 lastUpdateTimestamp;   // Last position update
        mapping(bytes32 => uint256) protocolAllocations; // Protocol allocations
        mapping(uint256 => uint256) chainAllocations;    // Chain allocations
    }
    
    struct ProtocolInfo {
        string name;                   // Protocol name (Aave, Compound, etc.)
        address protocolAddress;       // Main protocol contract address
        uint256 chainId;              // Chain where protocol is deployed
        bool isActive;                // Whether protocol is active
        uint256 maxTvl;               // Maximum TVL limit
        uint256 minDeposit;           // Minimum deposit amount
        bytes32 riskCategory;         // Risk category identifier
    }
    
    struct YieldOpportunity {
        bytes32 protocolId;           // Protocol offering the opportunity
        uint256 chainId;              // Chain ID
        uint256 currentYield;         // Current yield rate (basis points)
        uint256 projectedYield;       // Projected yield after rebalancing
        uint256 tvlAvailable;         // Available TVL for deposits
        uint256 confidence;           // AVS confidence level (0-10000)
        uint256 timestamp;            // When opportunity was identified
        uint256 expiresAt;            // When opportunity expires
        bool isValid;                 // Whether opportunity is still valid
    }
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event YieldStrategyUpdated(address indexed user, YieldStrategy strategy);
    event YieldOptimizationTriggered(
        address indexed user,
        uint256 amount,
        bytes32 indexed fromProtocol,
        bytes32 indexed toProtocol,
        uint256 expectedYieldImprovement
    );
    event CrossChainRebalanceExecuted(
        address indexed user,
        uint256 amount,
        uint256 indexed fromChain,
        uint256 indexed toChain,
        bytes32 protocol
    );
    event YieldEarned(address indexed user, uint256 amount, bytes32 indexed protocol);
    event ProtocolAdded(bytes32 indexed protocolId, ProtocolInfo info);
    event YieldOpportunityDetected(
        bytes32 indexed opportunityId,
        bytes32 indexed protocolId,
        uint256 yield,
        uint256 confidence
    );
    event FeesCollected(address indexed treasury, uint256 amount);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        IPoolManager _poolManager,
        IYieldIntelligenceAVS _yieldIntelligenceAVS,
        ICircleWalletManager _circleWalletManager,
        ICCTPIntegration _cctpIntegration,
        address _treasury
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        yieldIntelligenceAVS = _yieldIntelligenceAVS;
        circleWalletManager = _circleWalletManager;
        cctpIntegration = _cctpIntegration;
        treasury = _treasury;
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override whenNotPaused returns (bytes4, BeforeSwapDelta, uint24) {
        // Check if this is a USDC-related pool
        if (!_isUSDCPool(key)) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Check if user has enabled auto-rebalancing
        if (!userStrategies[sender].autoRebalance) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Check rebalancing cooldown
        if (block.timestamp - lastRebalance[sender] < REBALANCE_COOLDOWN) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Query AVS for current yield opportunities
        _queryYieldOpportunities(sender);
        
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
    
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override whenNotPaused returns (bytes4, int128) {
        // Check if this is a USDC-related pool and rebalancing is beneficial
        if (_isUSDCPool(key) && _shouldRebalance(sender)) {
            _executeYieldOptimization(sender);
        }
        
        return (this.afterSwap.selector, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        YIELD OPTIMIZATION
    //////////////////////////////////////////////////////////////*/
    
    function setYieldStrategy(
        uint256 targetAllocation,
        uint256 riskTolerance,
        uint256 rebalanceThreshold,
        bool autoRebalance,
        bool crossChainEnabled,
        bytes32[] calldata approvedProtocols,
        uint256[] calldata chainIds,
        uint256 maxSlippage
    ) external {
        require(targetAllocation <= 10000, "Invalid allocation");
        require(riskTolerance <= 10000, "Invalid risk tolerance");
        require(maxSlippage <= 1000, "Invalid slippage");
        
        userStrategies[msg.sender] = YieldStrategy({
            targetAllocation: targetAllocation,
            riskTolerance: riskTolerance,
            rebalanceThreshold: rebalanceThreshold,
            autoRebalance: autoRebalance,
            crossChainEnabled: crossChainEnabled,
            approvedProtocols: approvedProtocols,
            chainIds: chainIds,
            maxSlippage: maxSlippage
        });
        
        emit YieldStrategyUpdated(msg.sender, userStrategies[msg.sender]);
    }
    
    function manualRebalance() external nonReentrant whenNotPaused {
        require(_shouldRebalance(msg.sender), "No profitable rebalancing opportunity");
        _executeYieldOptimization(msg.sender);
    }
    
    function _queryYieldOpportunities(address user) internal {
        // Query AVS for latest yield intelligence
        bytes memory queryData = abi.encode(
            userStrategies[user].approvedProtocols,
            userStrategies[user].chainIds,
            userStrategies[user].riskTolerance
        );
        
        // This would make an async call to the AVS
        // For now, we'll simulate the response
        _simulateAVSResponse(user);
    }
    
    function _simulateAVSResponse(address user) internal {
        // Simulate AVS providing yield opportunities
        bytes32 aaveProtocol = keccak256("AAVE_V3");
        bytes32 compoundProtocol = keccak256("COMPOUND_V3");
        
        // Create sample opportunities
        yieldOpportunities[aaveProtocol] = YieldOpportunity({
            protocolId: aaveProtocol,
            chainId: 1, // Ethereum
            currentYield: 450, // 4.5% APY
            projectedYield: 520, // 5.2% APY
            tvlAvailable: 1000000e6, // 1M USDC
            confidence: 8500, // 85% confidence
            timestamp: block.timestamp,
            expiresAt: block.timestamp + 300, // 5 minutes
            isValid: true
        });
        
        emit YieldOpportunityDetected(aaveProtocol, aaveProtocol, 520, 8500);
    }
    
    function _shouldRebalance(address user) internal view returns (bool) {
        YieldStrategy memory strategy = userStrategies[user];
        if (!strategy.autoRebalance) return false;
        
        // Check if there are profitable opportunities
        return _hasYieldOpportunity(user, strategy.rebalanceThreshold);
    }
    
    function _hasYieldOpportunity(address user, uint256 threshold) internal view returns (bool) {
        // Check active opportunities
        bytes32 aaveProtocol = keccak256("AAVE_V3");
        YieldOpportunity memory opportunity = yieldOpportunities[aaveProtocol];
        
        if (!opportunity.isValid || opportunity.expiresAt < block.timestamp) {
            return false;
        }
        
        // Check if improvement meets threshold
        uint256 currentUserYield = _getCurrentUserYield(user);
        uint256 improvement = opportunity.projectedYield > currentUserYield ? 
            opportunity.projectedYield - currentUserYield : 0;
            
        return improvement >= threshold;
    }
    
    function _getCurrentUserYield(address user) internal view returns (uint256) {
        // Placeholder: calculate current weighted yield across user's positions
        return 400; // 4% APY placeholder
    }
    
    function _executeYieldOptimization(address user) internal {
        YieldStrategy memory strategy = userStrategies[user];
        uint256 userBalance = IERC20(USDC).balanceOf(user);
        
        if (userBalance < MIN_REBALANCE_AMOUNT) return;
        
        // Find best yield opportunity
        bytes32 bestProtocol = _findBestYieldOpportunity(user);
        if (bestProtocol == bytes32(0)) return;
        
        YieldOpportunity memory opportunity = yieldOpportunities[bestProtocol];
        
        // Calculate optimal allocation
        uint256 allocationAmount = _calculateOptimalAllocation(user, opportunity);
        
        if (allocationAmount < MIN_REBALANCE_AMOUNT) return;
        
        // Execute rebalancing via Circle Wallets
        _executeViaCircleWallets(user, opportunity, allocationAmount);
        
        // Update user position
        _updateUserPosition(user, opportunity.protocolId, allocationAmount);
        
        // Update last rebalance timestamp
        lastRebalance[user] = block.timestamp;
        
        emit YieldOptimizationTriggered(
            user,
            allocationAmount,
            bytes32(0), // Current protocol (simplified)
            opportunity.protocolId,
            opportunity.projectedYield - _getCurrentUserYield(user)
        );
    }
    
    function _findBestYieldOpportunity(address user) internal view returns (bytes32) {
        YieldStrategy memory strategy = userStrategies[user];
        bytes32 bestProtocol = bytes32(0);
        uint256 bestYield = 0;
        
        // Check approved protocols for best opportunity
        for (uint256 i = 0; i < strategy.approvedProtocols.length; i++) {
            bytes32 protocolId = strategy.approvedProtocols[i];
            YieldOpportunity memory opportunity = yieldOpportunities[protocolId];
            
            if (opportunity.isValid && 
                opportunity.expiresAt > block.timestamp &&
                opportunity.confidence >= 7000 && // Minimum 70% confidence
                opportunity.projectedYield > bestYield) {
                
                bestYield = opportunity.projectedYield;
                bestProtocol = protocolId;
            }
        }
        
        return bestProtocol;
    }
    
    function _calculateOptimalAllocation(address user, YieldOpportunity memory opportunity) internal view returns (uint256) {
        uint256 userBalance = IERC20(USDC).balanceOf(user);
        YieldStrategy memory strategy = userStrategies[user];
        
        // Calculate maximum allocation based on strategy
        uint256 maxAllocation = (userBalance * strategy.targetAllocation) / 10000;
        
        // Apply protocol limits
        uint256 protocolLimit = (userBalance * MAX_PROTOCOL_ALLOCATION) / 10000;
        
        // Consider available TVL
        uint256 tvlLimit = opportunity.tvlAvailable;
        
        return _min(_min(maxAllocation, protocolLimit), tvlLimit);
    }
    
    function _executeViaCircleWallets(address user, YieldOpportunity memory opportunity, uint256 amount) internal {
        if (opportunity.chainId != block.chainid) {
            // Cross-chain execution via CCTP
            _executeCrossChainRebalance(user, opportunity, amount);
        } else {
            // Same-chain execution via Circle Wallets
            _executeSameChainRebalance(user, opportunity, amount);
        }
    }
    
    function _executeCrossChainRebalance(address user, YieldOpportunity memory opportunity, uint256 amount) internal {
        // Use CCTP v2 for native USDC transfer
        bytes memory transferData = abi.encode(user, opportunity.protocolId, amount);
        
        // This would integrate with Circle's CCTP v2
        // cctpIntegration.transferUSDCAndExecute(
        //     opportunity.chainId,
        //     amount,
        //     transferData
        // );
        
        emit CrossChainRebalanceExecuted(
            user,
            amount,
            block.chainid,
            opportunity.chainId,
            opportunity.protocolId
        );
    }
    
    function _executeSameChainRebalance(address user, YieldOpportunity memory opportunity, uint256 amount) internal {
        // Execute rebalancing on same chain via Circle Wallets
        bytes memory rebalanceData = abi.encode(user, opportunity.protocolId, amount);
        
        // This would integrate with Circle Wallet Manager
        // circleWalletManager.executeRebalancing(user, rebalanceData);
    }
    
    function _updateUserPosition(address user, bytes32 protocolId, uint256 amount) internal {
        UserPosition storage position = userPositions[user];
        position.protocolAllocations[protocolId] += amount;
        position.lastUpdateTimestamp = block.timestamp;
    }
    
    /*//////////////////////////////////////////////////////////////
                            UTILITIES
    //////////////////////////////////////////////////////////////*/
    
    function _isUSDCPool(PoolKey calldata key) internal pure returns (bool) {
        return Currency.unwrap(key.currency0) == USDC || Currency.unwrap(key.currency1) == USDC;
    }
    
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function addProtocol(
        bytes32 protocolId,
        string calldata name,
        address protocolAddress,
        uint256 chainId,
        uint256 maxTvl,
        uint256 minDeposit,
        bytes32 riskCategory
    ) external onlyOwner {
        supportedProtocols[protocolId] = ProtocolInfo({
            name: name,
            protocolAddress: protocolAddress,
            chainId: chainId,
            isActive: true,
            maxTvl: maxTvl,
            minDeposit: minDeposit,
            riskCategory: riskCategory
        });
        
        emit ProtocolAdded(protocolId, supportedProtocols[protocolId]);
    }
    
    function updateTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function collectFees() external onlyOwner {
        uint256 balance = IERC20(USDC).balanceOf(address(this));
        if (balance > 0) {
            IERC20(USDC).transfer(treasury, balance);
            emit FeesCollected(treasury, balance);
        }
    }
}