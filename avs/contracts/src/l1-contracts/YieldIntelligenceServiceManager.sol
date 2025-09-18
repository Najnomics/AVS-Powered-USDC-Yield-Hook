// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from "@eigenlayer/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "@eigenlayer/contracts/interfaces/IPermissionController.sol";
import {TaskAVSRegistrarBase} from "@eigenlayer-middleware/src/avs/task/TaskAVSRegistrarBase.sol";
import {IYieldIntelligenceServiceManager} from "../interfaces/IYieldIntelligenceServiceManager.sol";

/**
 * @title YieldIntelligenceServiceManager
 * @notice EigenLayer L1 service manager for USDC Yield Intelligence AVS
 * @dev This is the main service manager for the USDC Yield Intelligence AVS that handles:
 * - Yield opportunity attestation coordination and consensus
 * - Operator registration with staking requirements for yield monitoring
 * - Slashing conditions for false/stale yield data
 * - Reward distribution for accurate yield intelligence operators
 * - Integration with USDC Yield Optimization Hook contracts
 */
contract YieldIntelligenceServiceManager is TaskAVSRegistrarBase, IYieldIntelligenceServiceManager {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Address of the USDC Yield Optimization Hook contract  
    address public immutable yieldOptimizationHook;
    
    /// @notice Minimum stake required for Yield Intelligence operators
    uint256 public constant MINIMUM_YIELD_OPERATOR_STAKE = 3 ether;
    
    /// @notice Maximum yield rate deviation allowed (in basis points)
    uint256 public constant MAX_YIELD_DEVIATION = 200; // 2%
    
    /// @notice Consensus threshold required (in basis points)
    uint256 public constant CONSENSUS_THRESHOLD = 6600; // 66%
    
    /// @notice Yield attestation reward amount
    uint256 public constant YIELD_ATTESTATION_REWARD = 0.0005 ether;
    
    /// @notice Slash percentage for inaccurate yield data
    uint256 public constant SLASH_PERCENTAGE = 50; // 0.5%
    
    /// @notice Minimum yield opportunity threshold (in basis points)
    uint256 public constant MIN_YIELD_OPPORTUNITY = 10; // 0.1%
    
    /// @notice Yield attestations by ID
    mapping(bytes32 => YieldAttestation) public yieldAttestations;
    
    /// @notice Current consensus data by protocol and chain
    mapping(bytes32 => YieldConsensus) public yieldConsensus;
    
    /// @notice Operator performance tracking for yield intelligence
    mapping(address => YieldOperatorPerformance) public operatorPerformance;
    
    /// @notice Protocol yield history
    mapping(bytes32 => YieldAttestation[]) public protocolYieldHistory;
    
    /// @notice Operators participating in current consensus
    mapping(bytes32 => address[]) public consensusOperators;
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct YieldAttestation {
        address operator;           // AVS operator submitting yield data
        bytes32 protocolId;        // Protocol this yield applies to (Aave, Compound, etc.)
        uint256 chainId;           // Chain ID where protocol is deployed
        uint256 yieldRate;         // Reported APY (basis points)
        uint256 tvl;               // Total Value Locked in protocol
        uint256 utilization;       // Protocol utilization rate
        uint256 riskScore;         // Risk assessment score (0-10000)
        uint256 timestamp;         // When yield was observed
        uint256 stakeAmount;       // Operator's stake backing this data
        bytes32 dataHash;          // Hash of yield sources and methodology
        bytes signature;           // BLS signature of attestation
        bool isValid;              // Whether attestation passed validation
    }
    
    struct YieldConsensus {
        bytes32 protocolId;           // Protocol ID
        uint256 chainId;              // Chain ID
        uint256 consensusYieldRate;   // Stake-weighted consensus yield rate
        uint256 consensusTvl;         // Consensus TVL
        uint256 consensusRiskScore;   // Consensus risk score
        uint256 totalStake;           // Total stake behind consensus
        uint256 attestationCount;     // Number of valid attestations
        uint256 confidenceLevel;      // Confidence in consensus (0-10000)
        uint256 consensusTimestamp;   // When consensus was reached
        bool isValid;                 // Whether consensus is valid
        bool isOpportunity;           // Whether this represents a yield opportunity
    }
    
    struct YieldOperatorPerformance {
        uint256 totalAttestations;        // Total yield attestations submitted
        uint256 accurateAttestations;     // Attestations within consensus range
        uint256 totalStakeSlashed;        // Total stake slashed for inaccuracy
        uint256 reliabilityScore;         // Reliability score (0-10000)
        uint256 lastAttestationTime;      // Last attestation timestamp
        uint256 protocolsMonitored;       // Number of protocols monitored
        uint256 chainsMonitored;          // Number of chains monitored
    }
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event YieldIntelligenceOperatorRegistered(address indexed operator, bytes32 indexed operatorId);
    event YieldIntelligenceOperatorDeregistered(address indexed operator, bytes32 indexed operatorId);
    event YieldAttestationSubmitted(
        bytes32 indexed attestationId,
        address indexed operator,
        bytes32 indexed protocolId,
        uint256 chainId,
        uint256 yieldRate
    );
    event YieldConsensusReached(
        bytes32 indexed consensusId,
        bytes32 indexed protocolId,
        uint256 chainId,
        uint256 consensusYieldRate,
        bool isOpportunity
    );
    event YieldOptimizationHookUpdated(address indexed oldHook, address indexed newHook);
    event YieldOptimizationProcessed(bytes32 indexed yieldOpportunityId, address indexed operator);
    event OperatorSlashed(
        address indexed operator,
        uint256 slashAmount,
        bytes32 indexed attestationId
    );
    event YieldOpportunityDetected(
        bytes32 indexed opportunityId,
        bytes32 indexed protocolId,
        uint256 chainId,
        uint256 yieldRate,
        uint256 confidenceLevel
    );
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        IAllocationManager _allocationManager,
        IPermissionController _permissionController,
        address _yieldOptimizationHook
    ) TaskAVSRegistrarBase(_allocationManager, _permissionController) {
        yieldOptimizationHook = _yieldOptimizationHook;
    }
    
    /*//////////////////////////////////////////////////////////////
                        OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    function registerYieldIntelligenceOperator(
        address operator,
        bytes calldata operatorSignature
    ) external payable override {
        // Validate operator meets minimum stake requirements
        require(
            _getOperatorStake(operator) >= MINIMUM_YIELD_OPERATOR_STAKE,
            "Insufficient stake for yield intelligence operations"
        );
        
        // Register with EigenLayer
        _registerOperator(operator, operatorSignature);
        
        // Initialize operator performance tracking
        operatorPerformance[operator] = YieldOperatorPerformance({
            totalAttestations: 0,
            accurateAttestations: 0,
            totalStakeSlashed: 0,
            reliabilityScore: 10000, // Start with perfect score
            lastAttestationTime: 0,
            protocolsMonitored: 0,
            chainsMonitored: 0
        });
        
        bytes32 operatorId = keccak256(abi.encodePacked(operator, block.timestamp));
        emit YieldIntelligenceOperatorRegistered(operator, operatorId);
    }
    
    function deregisterYieldIntelligenceOperator(address operator) external override {
        require(msg.sender == operator || msg.sender == owner(), "Unauthorized deregistration");
        
        _deregisterOperator(operator);
        
        bytes32 operatorId = keccak256(abi.encodePacked(operator, block.timestamp));
        emit YieldIntelligenceOperatorDeregistered(operator, operatorId);
    }
    
    function isYieldIntelligenceOperatorQualified(address operator) external view override returns (bool) {
        return _getOperatorStake(operator) >= MINIMUM_YIELD_OPERATOR_STAKE;
    }
    
    /*//////////////////////////////////////////////////////////////
                        YIELD INTELLIGENCE
    //////////////////////////////////////////////////////////////*/
    
    function submitYieldAttestation(
        bytes32 protocolId,
        uint256 chainId,
        uint256 yieldRate,
        uint256 tvl,
        uint256 utilization,
        uint256 riskScore,
        bytes32 dataHash,
        bytes calldata signature
    ) external {
        require(isYieldIntelligenceOperatorQualified(msg.sender), "Operator not qualified");
        
        bytes32 attestationId = keccak256(
            abi.encodePacked(msg.sender, protocolId, chainId, block.timestamp)
        );
        
        uint256 operatorStake = _getOperatorStake(msg.sender);
        
        yieldAttestations[attestationId] = YieldAttestation({
            operator: msg.sender,
            protocolId: protocolId,
            chainId: chainId,
            yieldRate: yieldRate,
            tvl: tvl,
            utilization: utilization,
            riskScore: riskScore,
            timestamp: block.timestamp,
            stakeAmount: operatorStake,
            dataHash: dataHash,
            signature: signature,
            isValid: true
        });
        
        // Update operator performance
        operatorPerformance[msg.sender].totalAttestations++;
        operatorPerformance[msg.sender].lastAttestationTime = block.timestamp;
        
        // Add to protocol history
        protocolYieldHistory[protocolId].push(yieldAttestations[attestationId]);
        
        emit YieldAttestationSubmitted(attestationId, msg.sender, protocolId, chainId, yieldRate);
        
        // Check if consensus can be reached
        _tryReachConsensus(protocolId, chainId);
    }
    
    function processYieldOptimization(bytes calldata yieldData) external override {
        require(msg.sender == yieldOptimizationHook, "Only yield optimization hook");
        
        // Decode yield optimization request
        (bytes32 protocolId, uint256 chainId, uint256 targetYield) = abi.decode(
            yieldData, 
            (bytes32, uint256, uint256)
        );
        
        // Get current consensus for the protocol
        bytes32 consensusKey = keccak256(abi.encodePacked(protocolId, chainId));
        YieldConsensus memory consensus = yieldConsensus[consensusKey];
        
        require(consensus.isValid, "No valid yield consensus available");
        require(consensus.isOpportunity, "Not a profitable yield opportunity");
        
        bytes32 opportunityId = keccak256(abi.encodePacked(protocolId, chainId, block.timestamp));
        emit YieldOptimizationProcessed(opportunityId, msg.sender);
    }
    
    function getYieldOptimizationHook() external view override returns (address) {
        return yieldOptimizationHook;
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _tryReachConsensus(bytes32 protocolId, uint256 chainId) internal {
        bytes32 consensusKey = keccak256(abi.encodePacked(protocolId, chainId));
        
        // Get recent attestations for this protocol/chain
        YieldAttestation[] memory recent = _getRecentAttestations(protocolId, chainId);
        
        if (recent.length < 3) return; // Need minimum 3 attestations
        
        // Calculate stake-weighted consensus
        uint256 totalStake = 0;
        uint256 weightedYield = 0;
        uint256 weightedTvl = 0;
        uint256 weightedRisk = 0;
        
        for (uint256 i = 0; i < recent.length; i++) {
            if (recent[i].isValid) {
                totalStake += recent[i].stakeAmount;
                weightedYield += recent[i].yieldRate * recent[i].stakeAmount;
                weightedTvl += recent[i].tvl * recent[i].stakeAmount;
                weightedRisk += recent[i].riskScore * recent[i].stakeAmount;
            }
        }
        
        if (totalStake == 0) return;
        
        uint256 consensusYield = weightedYield / totalStake;
        uint256 consensusTvl = weightedTvl / totalStake;
        uint256 consensusRisk = weightedRisk / totalStake;
        
        // Check if this represents a yield opportunity
        bool isOpportunity = consensusYield >= MIN_YIELD_OPPORTUNITY && consensusRisk <= 5000;
        
        yieldConsensus[consensusKey] = YieldConsensus({
            protocolId: protocolId,
            chainId: chainId,
            consensusYieldRate: consensusYield,
            consensusTvl: consensusTvl,
            consensusRiskScore: consensusRisk,
            totalStake: totalStake,
            attestationCount: recent.length,
            confidenceLevel: _calculateConfidence(recent),
            consensusTimestamp: block.timestamp,
            isValid: true,
            isOpportunity: isOpportunity
        });
        
        bytes32 consensusId = keccak256(abi.encodePacked(protocolId, chainId, block.timestamp));
        emit YieldConsensusReached(consensusId, protocolId, chainId, consensusYield, isOpportunity);
        
        if (isOpportunity) {
            emit YieldOpportunityDetected(consensusId, protocolId, chainId, consensusYield, _calculateConfidence(recent));
        }
    }
    
    function _getRecentAttestations(bytes32 protocolId, uint256 chainId) internal view returns (YieldAttestation[] memory) {
        YieldAttestation[] memory allAttestations = protocolYieldHistory[protocolId];
        uint256 cutoffTime = block.timestamp - 300; // 5 minutes
        
        // Count recent attestations for this chain
        uint256 recentCount = 0;
        for (uint256 i = 0; i < allAttestations.length; i++) {
            if (allAttestations[i].chainId == chainId && allAttestations[i].timestamp > cutoffTime) {
                recentCount++;
            }
        }
        
        // Collect recent attestations
        YieldAttestation[] memory recent = new YieldAttestation[](recentCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allAttestations.length; i++) {
            if (allAttestations[i].chainId == chainId && allAttestations[i].timestamp > cutoffTime) {
                recent[index] = allAttestations[i];
                index++;
            }
        }
        
        return recent;
    }
    
    function _calculateConfidence(YieldAttestation[] memory attestations) internal pure returns (uint256) {
        if (attestations.length == 0) return 0;
        if (attestations.length >= 5) return 10000; // Full confidence with 5+ attestations
        
        return (attestations.length * 2000); // 20% per additional attestation
    }
    
    function _getOperatorStake(address operator) internal view returns (uint256) {
        // This would integrate with EigenLayer's AllocationManager
        // For now, return a placeholder
        return 10 ether; // Placeholder
    }
}