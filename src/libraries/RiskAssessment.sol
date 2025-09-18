// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title RiskAssessment
 * @notice Library for protocol risk assessment and scoring
 * @dev Provides utilities for evaluating DeFi protocol risks for yield optimization
 */
library RiskAssessment {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_RISK_SCORE = 10000;
    
    // Risk weight factors (basis points)
    uint256 private constant TVL_WEIGHT = 2000;           // 20%
    uint256 private constant AUDIT_WEIGHT = 2500;         // 25%
    uint256 private constant TIME_WEIGHT = 1500;          // 15%
    uint256 private constant UTILIZATION_WEIGHT = 1000;   // 10%
    uint256 private constant GOVERNANCE_WEIGHT = 1500;    // 15%
    uint256 private constant LIQUIDITY_WEIGHT = 1500;     // 15%
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct ProtocolRisk {
        uint256 tvlScore;             // TVL-based risk score (0-10000)
        uint256 auditScore;           // Audit quality score (0-10000)
        uint256 timeScore;            // Time in operation score (0-10000)
        uint256 utilizationScore;     // Utilization rate score (0-10000)
        uint256 governanceScore;      // Governance risk score (0-10000)
        uint256 liquidityScore;       // Liquidity risk score (0-10000)
        uint256 compositeScore;       // Weighted composite score (0-10000)
        RiskCategory category;        // Risk category
        string[] riskFactors;         // Specific risk factors identified
    }
    
    struct ProtocolMetrics {
        uint256 tvl;                  // Total Value Locked (USDC)
        uint256 utilizationRate;      // Current utilization rate (basis points)
        uint256 timeInOperation;      // Days since deployment
        uint256 maxWithdrawal;        // Maximum immediate withdrawal capacity
        uint256 averageYield;         // Historical average yield (basis points)
        uint256 yieldVolatility;      // Yield volatility score (0-10000)
        bool hasAudit;                // Whether protocol has been audited
        uint256 auditScore;           // Audit quality score (0-10000)
        bool hasGovernanceToken;      // Whether protocol has governance token
        uint256 governanceRisk;       // Governance centralization risk (0-10000)
    }
    
    enum RiskCategory {
        VERY_LOW,    // 0-2000   (0-20%)
        LOW,         // 2001-4000 (20-40%)
        MEDIUM,      // 4001-6000 (40-60%)
        HIGH,        // 6001-8000 (60-80%)
        VERY_HIGH    // 8001-10000 (80-100%)
    }
    
    /*//////////////////////////////////////////////////////////////
                        RISK CALCULATIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calculate comprehensive protocol risk score
     * @param metrics Protocol metrics
     * @return risk Complete risk assessment
     */
    function assessProtocolRisk(ProtocolMetrics memory metrics)
        internal pure returns (ProtocolRisk memory risk)
    {
        risk.tvlScore = _calculateTVLScore(metrics.tvl);
        risk.auditScore = _calculateAuditScore(metrics.hasAudit, metrics.auditScore);
        risk.timeScore = _calculateTimeScore(metrics.timeInOperation);
        risk.utilizationScore = _calculateUtilizationScore(metrics.utilizationRate);
        risk.governanceScore = _calculateGovernanceScore(
            metrics.hasGovernanceToken,
            metrics.governanceRisk
        );
        risk.liquidityScore = _calculateLiquidityScore(
            metrics.tvl,
            metrics.maxWithdrawal,
            metrics.utilizationRate
        );
        
        // Calculate weighted composite score
        risk.compositeScore = (
            risk.tvlScore * TVL_WEIGHT +
            risk.auditScore * AUDIT_WEIGHT +
            risk.timeScore * TIME_WEIGHT +
            risk.utilizationScore * UTILIZATION_WEIGHT +
            risk.governanceScore * GOVERNANCE_WEIGHT +
            risk.liquidityScore * LIQUIDITY_WEIGHT
        ) / BASIS_POINTS;
        
        risk.category = _categorizeRisk(risk.compositeScore);
        risk.riskFactors = _identifyRiskFactors(risk, metrics);
    }
    
    /**
     * @notice Compare risk between two protocols
     * @param riskA First protocol risk
     * @param riskB Second protocol risk
     * @return isSafer Whether protocol A is safer than B
     * @return riskDifference Risk score difference (A - B)
     */
    function compareProtocolRisk(
        ProtocolRisk memory riskA,
        ProtocolRisk memory riskB
    ) internal pure returns (bool isSafer, int256 riskDifference) {
        riskDifference = int256(riskA.compositeScore) - int256(riskB.compositeScore);
        isSafer = riskDifference < 0; // Lower score = safer
    }
    
    /**
     * @notice Check if protocol meets risk tolerance
     * @param risk Protocol risk assessment
     * @param riskTolerance User risk tolerance (0-10000)
     * @return meetsRequirements Whether protocol meets risk tolerance
     * @return riskMargin Safety margin (tolerance - actual risk)
     */
    function meetsRiskTolerance(
        ProtocolRisk memory risk,
        uint256 riskTolerance
    ) internal pure returns (bool meetsRequirements, int256 riskMargin) {
        riskMargin = int256(riskTolerance) - int256(risk.compositeScore);
        meetsRequirements = riskMargin >= 0;
    }
    
    /*//////////////////////////////////////////////////////////////
                        RISK SCORING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calculate TVL-based risk score
     * @param tvl Total Value Locked in USDC
     * @return score Risk score (0-10000, lower is better)
     */
    function _calculateTVLScore(uint256 tvl) private pure returns (uint256 score) {
        // Higher TVL = lower risk
        if (tvl >= 1000000000e6) {        // >= $1B
            score = 500;   // Very low risk
        } else if (tvl >= 100000000e6) {  // >= $100M
            score = 1500;  // Low risk
        } else if (tvl >= 10000000e6) {   // >= $10M
            score = 3000;  // Medium risk
        } else if (tvl >= 1000000e6) {    // >= $1M
            score = 6000;  // High risk
        } else {
            score = 9000;  // Very high risk
        }
    }
    
    /**
     * @notice Calculate audit-based risk score
     * @param hasAudit Whether protocol has been audited
     * @param auditScore Quality of audit (0-10000)
     * @return score Risk score (0-10000, lower is better)
     */
    function _calculateAuditScore(bool hasAudit, uint256 auditScore)
        private pure returns (uint256 score)
    {
        if (!hasAudit) {
            score = 8000; // High risk for unaudited protocols
        } else {
            // Invert audit score (high audit quality = low risk)
            score = MAX_RISK_SCORE - auditScore;
        }
    }
    
    /**
     * @notice Calculate time-based risk score
     * @param daysInOperation Days since protocol deployment
     * @return score Risk score (0-10000, lower is better)
     */
    function _calculateTimeScore(uint256 daysInOperation)
        private pure returns (uint256 score)
    {
        // Longer operation = lower risk
        if (daysInOperation >= 730) {       // >= 2 years
            score = 1000;  // Very low risk
        } else if (daysInOperation >= 365) { // >= 1 year
            score = 2500;  // Low risk
        } else if (daysInOperation >= 180) { // >= 6 months
            score = 4000;  // Medium risk
        } else if (daysInOperation >= 90) {  // >= 3 months
            score = 6500;  // High risk
        } else {
            score = 9000;  // Very high risk
        }
    }
    
    /**
     * @notice Calculate utilization-based risk score
     * @param utilizationRate Current utilization rate (basis points)
     * @return score Risk score (0-10000, lower is better)
     */
    function _calculateUtilizationScore(uint256 utilizationRate)
        private pure returns (uint256 score)
    {
        // Moderate utilization is ideal (70-85%)
        if (utilizationRate >= 7000 && utilizationRate <= 8500) {
            score = 1000;  // Optimal range
        } else if (utilizationRate >= 6000 && utilizationRate <= 9000) {
            score = 2500;  // Good range
        } else if (utilizationRate >= 5000 && utilizationRate <= 9500) {
            score = 4000;  // Acceptable range
        } else if (utilizationRate >= 3000 && utilizationRate <= 9800) {
            score = 6000;  // Suboptimal range
        } else {
            score = 8500;  // Poor utilization (too low or too high)
        }
    }
    
    /**
     * @notice Calculate governance-based risk score
     * @param hasGovernanceToken Whether protocol has governance token
     * @param governanceRisk Governance centralization risk (0-10000)
     * @return score Risk score (0-10000, lower is better)
     */
    function _calculateGovernanceScore(bool hasGovernanceToken, uint256 governanceRisk)
        private pure returns (uint256 score)
    {
        if (!hasGovernanceToken) {
            score = 7000; // Centralized governance = higher risk
        } else {
            score = governanceRisk; // Use provided governance risk score
        }
    }
    
    /**
     * @notice Calculate liquidity-based risk score
     * @param tvl Total Value Locked
     * @param maxWithdrawal Maximum immediate withdrawal capacity
     * @param utilizationRate Current utilization rate
     * @return score Risk score (0-10000, lower is better)
     */
    function _calculateLiquidityScore(
        uint256 tvl,
        uint256 maxWithdrawal,
        uint256 utilizationRate
    ) private pure returns (uint256 score) {
        if (tvl == 0) return 10000;
        
        uint256 liquidityRatio = (maxWithdrawal * BASIS_POINTS) / tvl;
        
        // Good liquidity: can withdraw 20%+ immediately
        if (liquidityRatio >= 2000) {
            score = 1000;
        } else if (liquidityRatio >= 1000) {
            score = 3000;
        } else if (liquidityRatio >= 500) {
            score = 5000;
        } else {
            score = 8000; // Poor liquidity
        }
        
        // Adjust for high utilization (reduces available liquidity)
        if (utilizationRate >= 9000) {
            score += 1500; // Penalty for high utilization
        }
        
        // Cap at maximum risk score
        if (score > MAX_RISK_SCORE) {
            score = MAX_RISK_SCORE;
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Categorize risk score into risk category
     * @param riskScore Composite risk score (0-10000)
     * @return category Risk category
     */
    function _categorizeRisk(uint256 riskScore)
        private pure returns (RiskCategory category)
    {
        if (riskScore <= 2000) {
            category = RiskCategory.VERY_LOW;
        } else if (riskScore <= 4000) {
            category = RiskCategory.LOW;
        } else if (riskScore <= 6000) {
            category = RiskCategory.MEDIUM;
        } else if (riskScore <= 8000) {
            category = RiskCategory.HIGH;
        } else {
            category = RiskCategory.VERY_HIGH;
        }
    }
    
    /**
     * @notice Identify specific risk factors for a protocol
     * @param risk Risk assessment results
     * @param metrics Protocol metrics
     * @return riskFactors Array of identified risk factors
     */
    function _identifyRiskFactors(
        ProtocolRisk memory risk,
        ProtocolMetrics memory metrics
    ) private pure returns (string[] memory riskFactors) {
        // Count potential risk factors
        uint256 factorCount = 0;
        
        if (risk.tvlScore >= 6000) factorCount++;
        if (risk.auditScore >= 6000) factorCount++;
        if (risk.timeScore >= 6000) factorCount++;
        if (risk.utilizationScore >= 6000) factorCount++;
        if (risk.governanceScore >= 6000) factorCount++;
        if (risk.liquidityScore >= 6000) factorCount++;
        
        riskFactors = new string[](factorCount);
        uint256 index = 0;
        
        if (risk.tvlScore >= 6000) {
            riskFactors[index++] = "LOW_TVL";
        }
        if (risk.auditScore >= 6000) {
            riskFactors[index++] = "AUDIT_CONCERNS";
        }
        if (risk.timeScore >= 6000) {
            riskFactors[index++] = "NEW_PROTOCOL";
        }
        if (risk.utilizationScore >= 6000) {
            riskFactors[index++] = "POOR_UTILIZATION";
        }
        if (risk.governanceScore >= 6000) {
            riskFactors[index++] = "GOVERNANCE_RISK";
        }
        if (risk.liquidityScore >= 6000) {
            riskFactors[index++] = "LIQUIDITY_RISK";
        }
    }
    
    /**
     * @notice Calculate risk-adjusted allocation limit
     * @param riskScore Protocol risk score (0-10000)
     * @param userRiskTolerance User risk tolerance (0-10000)
     * @param maxAllocationPercentage Maximum allocation percentage (basis points)
     * @return adjustedLimit Risk-adjusted allocation limit (basis points)
     */
    function calculateRiskAdjustedAllocationLimit(
        uint256 riskScore,
        uint256 userRiskTolerance,
        uint256 maxAllocationPercentage
    ) internal pure returns (uint256 adjustedLimit) {
        if (riskScore > userRiskTolerance) {
            return 0; // No allocation if risk exceeds tolerance
        }
        
        // Reduce allocation based on risk level
        uint256 riskPenalty = (riskScore * riskScore) / BASIS_POINTS;
        uint256 reductionFactor = BASIS_POINTS - riskPenalty;
        
        adjustedLimit = (maxAllocationPercentage * reductionFactor) / BASIS_POINTS;
    }
    
    /**
     * @notice Get risk category string representation
     * @param category Risk category enum
     * @return categoryString String representation
     */
    function getRiskCategoryString(RiskCategory category)
        internal pure returns (string memory categoryString)
    {
        if (category == RiskCategory.VERY_LOW) {
            categoryString = "VERY_LOW";
        } else if (category == RiskCategory.LOW) {
            categoryString = "LOW";
        } else if (category == RiskCategory.MEDIUM) {
            categoryString = "MEDIUM";
        } else if (category == RiskCategory.HIGH) {
            categoryString = "HIGH";
        } else {
            categoryString = "VERY_HIGH";
        }
    }
}