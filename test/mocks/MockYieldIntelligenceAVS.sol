// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../src/interfaces/IYieldIntelligenceAVS.sol";

/**
 * @title MockYieldIntelligenceAVS
 * @notice Mock implementation of the Yield Intelligence AVS for testing
 */
contract MockYieldIntelligenceAVS is IYieldIntelligenceAVS {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    mapping(bytes32 => mapping(uint256 => YieldData)) private yieldData;
    mapping(bytes32 => mapping(uint256 => YieldOpportunity)) private yieldOpportunities;
    mapping(bytes32 => OptimizationResult) private optimizationResults;
    
    bytes32[] private supportedProtocolIds;
    string[] private protocolNames;
    uint256[][] private supportedChainIds;
    
    struct OptimizationResult {
        bool isReady;
        YieldOpportunity[] recommendations;
        uint256 confidence;
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getYieldData(bytes32 protocolId, uint256 chainId)
        external view override returns (YieldData memory)
    {
        return yieldData[protocolId][chainId];
    }
    
    function getBatchYieldData(bytes32[] calldata protocolIds, uint256[] calldata chainIds)
        external view override returns (YieldData[] memory yieldDataArray)
    {
        require(protocolIds.length == chainIds.length, "Array length mismatch");
        
        yieldDataArray = new YieldData[](protocolIds.length);
        for (uint256 i = 0; i < protocolIds.length; i++) {
            yieldDataArray[i] = yieldData[protocolIds[i]][chainIds[i]];
        }
    }
    
    function getYieldOpportunities(
        uint256 riskTolerance,
        uint256 minAmount,
        uint256 maxAmount,
        bytes32[] calldata approvedProtocols,
        uint256[] calldata approvedChains
    ) external view override returns (YieldOpportunity[] memory opportunities) {
        // Simplified mock implementation
        uint256 count = 0;
        
        // Count valid opportunities
        for (uint256 i = 0; i < approvedProtocols.length; i++) {
            for (uint256 j = 0; j < approvedChains.length; j++) {
                YieldOpportunity memory opp = yieldOpportunities[approvedProtocols[i]][approvedChains[j]];
                if (opp.projectedYield > 0 && opp.maxAmount >= minAmount) {
                    count++;
                }
            }
        }
        
        // Collect opportunities
        opportunities = new YieldOpportunity[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < approvedProtocols.length; i++) {
            for (uint256 j = 0; j < approvedChains.length; j++) {
                YieldOpportunity memory opp = yieldOpportunities[approvedProtocols[i]][approvedChains[j]];
                if (opp.projectedYield > 0 && opp.maxAmount >= minAmount) {
                    opportunities[index] = opp;
                    index++;
                }
            }
        }
    }
    
    function getRiskMetrics(bytes32 protocolId, uint256 chainId)
        external pure override returns (RiskMetrics memory riskMetrics)
    {
        // Return mock risk metrics
        riskMetrics = RiskMetrics({
            protocolRisk: 2000,     // 20% risk
            liquidityRisk: 1500,    // 15% risk
            smartContractRisk: 1000, // 10% risk
            governanceRisk: 500,    // 5% risk
            overallRisk: 2500,      // 25% overall risk
            riskCategory: "LOW"
        });
    }
    
    function evaluateYieldImprovement(
        uint256 currentYield,
        uint256 targetYield,
        uint256 amount,
        uint256 threshold
    ) external pure override returns (bool isWorthwhile, uint256 projectedImprovement) {
        if (targetYield > currentYield) {
            uint256 improvement = targetYield - currentYield;
            projectedImprovement = (amount * improvement) / 10000; // Convert from basis points
            isWorthwhile = improvement >= threshold;
        }
    }
    
    function getSupportedProtocols()
        external view override returns (
            bytes32[] memory protocolIds,
            string[] memory names,
            uint256[][] memory chainIds
        )
    {
        return (supportedProtocolIds, protocolNames, supportedChainIds);
    }
    
    /*//////////////////////////////////////////////////////////////
                        YIELD OPTIMIZATION
    //////////////////////////////////////////////////////////////*/
    
    function submitOptimizationRequest(
        address userAddress,
        bytes32[] calldata currentAllocations,
        uint256 targetAmount,
        bytes calldata constraints
    ) external override returns (bytes32 requestId) {
        requestId = keccak256(abi.encodePacked(userAddress, block.timestamp));
        
        // Mock optimization result
        YieldOpportunity[] memory recommendations = new YieldOpportunity[](1);
        recommendations[0] = YieldOpportunity({
            protocolId: keccak256("AAVE_V3"),
            chainId: block.chainid,
            projectedYield: 520, // 5.2%
            currentYield: 400,   // 4.0%
            improvement: 120,    // 1.2%
            confidence: 8500,    // 85%
            maxAmount: 1000000e6, // 1M USDC
            expiresAt: block.timestamp + 300, // 5 minutes
            additionalData: ""
        });
        
        optimizationResults[requestId] = OptimizationResult({
            isReady: true,
            recommendations: recommendations,
            confidence: 8500
        });
        
        emit OptimizationRequested(requestId, userAddress, targetAmount);
        emit OptimizationCompleted(requestId, userAddress, 1);
    }
    
    function getOptimizationResult(bytes32 requestId)
        external view override returns (
            bool isReady,
            YieldOpportunity[] memory recommendations,
            uint256 confidence
        )
    {
        OptimizationResult memory result = optimizationResults[requestId];
        return (result.isReady, result.recommendations, result.confidence);
    }
    
    function validateYieldOpportunity(
        YieldOpportunity calldata opportunity,
        uint256 amount
    ) external view override returns (
        bool isValid,
        uint256 updatedYield,
        uint256 updatedConfidence
    ) {
        // Mock validation - opportunity is valid if not expired
        isValid = opportunity.expiresAt > block.timestamp;
        updatedYield = opportunity.projectedYield;
        updatedConfidence = opportunity.confidence;
        
        // Reduce confidence if amount is large
        if (amount > opportunity.maxAmount / 2) {
            updatedConfidence = (updatedConfidence * 80) / 100; // 20% reduction
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        MOCK HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function setYieldData(
        bytes32 protocolId,
        uint256 chainId,
        uint256 currentYield,
        uint256 tvl,
        uint256 confidence
    ) external {
        yieldData[protocolId][chainId] = YieldData({
            protocolId: protocolId,
            chainId: chainId,
            currentYield: currentYield,
            tvl: tvl,
            utilization: 7500, // 75%
            riskScore: 2000,   // 20%
            confidence: confidence,
            timestamp: block.timestamp,
            isValid: true
        });
        
        emit YieldDataUpdated(protocolId, chainId, currentYield, confidence);
    }
    
    function setYieldOpportunity(
        bytes32 protocolId,
        uint256 chainId,
        uint256 projectedYield,
        uint256 maxAmount,
        uint256 confidence
    ) external {
        yieldOpportunities[protocolId][chainId] = YieldOpportunity({
            protocolId: protocolId,
            chainId: chainId,
            projectedYield: projectedYield,
            currentYield: 400, // Default current yield
            improvement: projectedYield > 400 ? projectedYield - 400 : 0,
            confidence: confidence,
            maxAmount: maxAmount,
            expiresAt: block.timestamp + 600, // 10 minutes
            additionalData: ""
        });
        
        emit YieldOpportunityDetected(
            keccak256(abi.encodePacked(protocolId, chainId)),
            protocolId,
            chainId,
            projectedYield,
            projectedYield > 400 ? projectedYield - 400 : 0
        );
    }
    
    function addSupportedProtocol(
        bytes32 protocolId,
        string calldata name,
        uint256[] calldata chainIds
    ) external {
        supportedProtocolIds.push(protocolId);
        protocolNames.push(name);
        supportedChainIds.push(chainIds);
    }
    
    function clearYieldOpportunities() external {
        // Clear all yield opportunities (for testing edge cases)
        for (uint256 i = 0; i < supportedProtocolIds.length; i++) {
            for (uint256 j = 0; j < supportedChainIds[i].length; j++) {
                delete yieldOpportunities[supportedProtocolIds[i]][supportedChainIds[i][j]];
            }
        }
    }
    
    function updateRiskMetrics(
        bytes32 protocolId,
        uint256 chainId,
        uint256 newRiskScore
    ) external {
        // Update risk score for a protocol
        emit RiskMetricsUpdated(protocolId, chainId, newRiskScore);
    }
}