// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IYieldIntelligenceAVS
 * @notice Interface for the EigenLayer USDC Yield Intelligence AVS
 * @dev This interface defines the methods for interacting with the AVS
 *      to get yield intelligence data and submit yield optimization requests
 */
interface IYieldIntelligenceAVS {
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct YieldData {
        bytes32 protocolId;           // Protocol identifier
        uint256 chainId;              // Chain ID where protocol is deployed  
        uint256 currentYield;         // Current yield rate (basis points)
        uint256 tvl;                  // Total Value Locked
        uint256 utilization;          // Protocol utilization rate
        uint256 riskScore;            // Risk assessment score (0-10000)
        uint256 confidence;           // Consensus confidence level (0-10000)
        uint256 timestamp;            // Data timestamp
        bool isValid;                 // Whether data is valid
    }
    
    struct YieldOpportunity {
        bytes32 protocolId;           // Protocol offering opportunity
        uint256 chainId;              // Target chain
        uint256 projectedYield;       // Projected yield after optimization
        uint256 currentYield;         // Current best yield for comparison
        uint256 improvement;          // Expected improvement (basis points)
        uint256 confidence;           // AVS confidence in opportunity
        uint256 maxAmount;            // Maximum amount for this opportunity
        uint256 expiresAt;            // When opportunity expires
        bytes additionalData;         // Additional protocol-specific data
    }
    
    struct RiskMetrics {
        uint256 protocolRisk;         // Protocol-specific risk score
        uint256 liquidityRisk;        // Liquidity risk assessment
        uint256 smartContractRisk;    // Smart contract risk score
        uint256 governanceRisk;       // Governance risk score
        uint256 overallRisk;          // Composite risk score
        string riskCategory;          // Risk category (LOW, MEDIUM, HIGH)
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get current yield data for a specific protocol
     * @param protocolId Protocol identifier
     * @param chainId Chain ID
     * @return yieldData Current yield data with consensus information
     */
    function getYieldData(bytes32 protocolId, uint256 chainId) 
        external view returns (YieldData memory yieldData);
    
    /**
     * @notice Get yield data for multiple protocols
     * @param protocolIds Array of protocol identifiers
     * @param chainIds Array of chain IDs (must match protocolIds length)
     * @return yieldDataArray Array of yield data
     */
    function getBatchYieldData(bytes32[] calldata protocolIds, uint256[] calldata chainIds)
        external view returns (YieldData[] memory yieldDataArray);
    
    /**
     * @notice Get best yield opportunities for given constraints
     * @param riskTolerance Risk tolerance level (0-10000)
     * @param minAmount Minimum amount to invest
     * @param maxAmount Maximum amount to invest
     * @param approvedProtocols Whitelisted protocols (empty for all)
     * @param approvedChains Whitelisted chains (empty for all)
     * @return opportunities Array of ranked yield opportunities
     */
    function getYieldOpportunities(
        uint256 riskTolerance,
        uint256 minAmount,
        uint256 maxAmount,
        bytes32[] calldata approvedProtocols,
        uint256[] calldata approvedChains
    ) external view returns (YieldOpportunity[] memory opportunities);
    
    /**
     * @notice Get risk metrics for a protocol
     * @param protocolId Protocol identifier
     * @param chainId Chain ID
     * @return riskMetrics Comprehensive risk assessment
     */
    function getRiskMetrics(bytes32 protocolId, uint256 chainId)
        external view returns (RiskMetrics memory riskMetrics);
    
    /**
     * @notice Check if yield opportunity meets minimum improvement threshold
     * @param currentYield Current yield rate
     * @param targetYield Target yield rate
     * @param amount Amount to be moved
     * @param threshold Minimum improvement threshold (basis points)
     * @return isWorthwhile Whether the opportunity is worthwhile
     * @return projectedImprovement Projected annual improvement amount
     */
    function evaluateYieldImprovement(
        uint256 currentYield,
        uint256 targetYield,
        uint256 amount,
        uint256 threshold
    ) external pure returns (bool isWorthwhile, uint256 projectedImprovement);
    
    /**
     * @notice Get supported protocols on AVS
     * @return protocolIds Array of supported protocol identifiers
     * @return names Array of protocol names
     * @return chainIds Array of supported chain IDs for each protocol
     */
    function getSupportedProtocols() 
        external view returns (
            bytes32[] memory protocolIds, 
            string[] memory names,
            uint256[][] memory chainIds
        );
    
    /*//////////////////////////////////////////////////////////////
                        YIELD OPTIMIZATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Submit a yield optimization request to the AVS
     * @param userAddress User requesting optimization
     * @param currentAllocations Current protocol allocations
     * @param targetAmount Amount to optimize
     * @param constraints User constraints (risk tolerance, approved protocols, etc.)
     * @return requestId Request identifier for tracking
     */
    function submitOptimizationRequest(
        address userAddress,
        bytes32[] calldata currentAllocations,
        uint256 targetAmount,
        bytes calldata constraints
    ) external returns (bytes32 requestId);
    
    /**
     * @notice Get optimization result for a request
     * @param requestId Request identifier
     * @return isReady Whether result is ready
     * @return recommendations Array of recommended yield opportunities
     * @return confidence Overall confidence in recommendations
     */
    function getOptimizationResult(bytes32 requestId)
        external view returns (
            bool isReady,
            YieldOpportunity[] memory recommendations,
            uint256 confidence
        );
    
    /**
     * @notice Validate a yield optimization before execution
     * @param opportunity Yield opportunity to validate
     * @param amount Amount to be moved
     * @return isValid Whether opportunity is still valid
     * @return updatedYield Updated yield rate if different
     * @return updatedConfidence Updated confidence level
     */
    function validateYieldOpportunity(
        YieldOpportunity calldata opportunity,
        uint256 amount
    ) external view returns (
        bool isValid,
        uint256 updatedYield,
        uint256 updatedConfidence
    );
    
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event YieldDataUpdated(
        bytes32 indexed protocolId,
        uint256 indexed chainId,
        uint256 newYield,
        uint256 confidence
    );
    
    event YieldOpportunityDetected(
        bytes32 indexed opportunityId,
        bytes32 indexed protocolId,
        uint256 indexed chainId,
        uint256 yield,
        uint256 improvement
    );
    
    event OptimizationRequested(
        bytes32 indexed requestId,
        address indexed user,
        uint256 amount
    );
    
    event OptimizationCompleted(
        bytes32 indexed requestId,
        address indexed user,
        uint256 recommendationCount
    );
    
    event RiskMetricsUpdated(
        bytes32 indexed protocolId,
        uint256 indexed chainId,
        uint256 newRiskScore
    );
    
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidProtocolId();
    error UnsupportedChain();
    error InsufficientConfidence();
    error YieldDataStale();
    error OptimizationRequestNotFound();
    error InvalidRiskTolerance();
    error AmountTooSmall();
    error AmountTooLarge();
}