// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title YieldCalculations
 * @notice Library for USDC yield optimization calculations
 * @dev Provides utilities for APY calculations, compound interest, and yield comparisons
 */
library YieldCalculations {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant PRECISION = 1e18;
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct YieldData {
        uint256 principal;            // Principal amount (USDC)
        uint256 apy;                  // Annual Percentage Yield (basis points)
        uint256 duration;             // Investment duration (seconds)
        uint256 compoundFrequency;    // Compounding frequency per year
        uint256 riskAdjustment;       // Risk adjustment factor (basis points)
        uint256 gasCosts;             // Estimated gas costs (USDC)
        uint256 protocolFees;         // Protocol fees (USDC)
    }
    
    struct ComparisonResult {
        uint256 netYieldDifference;   // Net yield difference (USDC)
        uint256 percentageImprovement; // Percentage improvement (basis points)
        bool isWorthwhile;            // Whether rebalancing is profitable
        uint256 breakEvenTime;        // Time to break even (seconds)
        uint256 projectedAnnualBenefit; // Annual benefit projection (USDC)
    }
    
    /*//////////////////////////////////////////////////////////////
                        YIELD CALCULATIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calculate simple interest yield
     * @param principal Principal amount
     * @param apy Annual percentage yield (basis points)
     * @param duration Duration in seconds
     * @return yield Simple interest yield
     */
    function calculateSimpleYield(
        uint256 principal,
        uint256 apy,
        uint256 duration
    ) internal pure returns (uint256 yield) {
        yield = (principal * apy * duration) / (BASIS_POINTS * SECONDS_PER_YEAR);
    }
    
    /**
     * @notice Calculate compound interest yield
     * @param principal Principal amount
     * @param apy Annual percentage yield (basis points)
     * @param duration Duration in seconds
     * @param compoundFrequency Compounding frequency per year
     * @return yield Compound interest yield
     */
    function calculateCompoundYield(
        uint256 principal,
        uint256 apy,
        uint256 duration,
        uint256 compoundFrequency
    ) internal pure returns (uint256 yield) {
        if (compoundFrequency == 0) {
            return calculateSimpleYield(principal, apy, duration);
        }
        
        // A = P(1 + r/n)^(nt) - P
        // Where: P = principal, r = annual rate, n = compound frequency, t = time in years
        
        uint256 rate = (apy * PRECISION) / BASIS_POINTS;
        uint256 timeInYears = (duration * PRECISION) / SECONDS_PER_YEAR;
        uint256 ratePerPeriod = rate / compoundFrequency;
        uint256 periods = (compoundFrequency * timeInYears) / PRECISION;
        
        uint256 compoundFactor = _power(
            PRECISION + ratePerPeriod,
            periods,
            PRECISION
        );
        
        uint256 finalAmount = (principal * compoundFactor) / PRECISION;
        yield = finalAmount > principal ? finalAmount - principal : 0;
    }
    
    /**
     * @notice Calculate risk-adjusted yield
     * @param data Yield data including risk adjustment
     * @return adjustedYield Risk-adjusted yield
     */
    function calculateRiskAdjustedYield(YieldData memory data)
        internal pure returns (uint256 adjustedYield)
    {
        uint256 grossYield = calculateCompoundYield(
            data.principal,
            data.apy,
            data.duration,
            data.compoundFrequency
        );
        
        // Apply risk adjustment (reduce yield based on risk)
        uint256 riskPenalty = (grossYield * data.riskAdjustment) / BASIS_POINTS;
        grossYield = grossYield > riskPenalty ? grossYield - riskPenalty : 0;
        
        // Subtract costs
        uint256 totalCosts = data.gasCosts + data.protocolFees;
        adjustedYield = grossYield > totalCosts ? grossYield - totalCosts : 0;
    }
    
    /**
     * @notice Calculate net yield after all costs and risks
     * @param data Yield data
     * @return netYield Net yield amount
     * @return effectiveAPY Effective APY after costs (basis points)
     */
    function calculateNetYield(YieldData memory data)
        internal pure returns (uint256 netYield, uint256 effectiveAPY)
    {
        netYield = calculateRiskAdjustedYield(data);
        
        if (data.principal > 0 && data.duration > 0) {
            // Calculate effective APY: (netYield / principal) * (1 year / duration) * 100%
            effectiveAPY = (netYield * SECONDS_PER_YEAR * BASIS_POINTS) / 
                          (data.principal * data.duration);
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        YIELD COMPARISONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Compare two yield opportunities
     * @param currentData Current yield position
     * @param newData New yield opportunity
     * @param rebalanceCosts Costs associated with rebalancing
     * @return result Comparison result
     */
    function compareYieldOpportunities(
        YieldData memory currentData,
        YieldData memory newData,
        uint256 rebalanceCosts
    ) internal pure returns (ComparisonResult memory result) {
        (uint256 currentNetYield,) = calculateNetYield(currentData);
        (uint256 newNetYield,) = calculateNetYield(newData);
        
        // Account for rebalancing costs
        newNetYield = newNetYield > rebalanceCosts ? newNetYield - rebalanceCosts : 0;
        
        if (newNetYield > currentNetYield) {
            result.netYieldDifference = newNetYield - currentNetYield;
            result.percentageImprovement = (result.netYieldDifference * BASIS_POINTS) / currentNetYield;
            result.isWorthwhile = result.netYieldDifference > 0;
            
            // Calculate break-even time
            if (newData.apy > currentData.apy) {
                uint256 apyDifference = newData.apy - currentData.apy;
                result.breakEvenTime = (rebalanceCosts * SECONDS_PER_YEAR * BASIS_POINTS) / 
                                     (newData.principal * apyDifference);
            }
            
            // Project annual benefit
            result.projectedAnnualBenefit = (result.netYieldDifference * SECONDS_PER_YEAR) / 
                                          newData.duration;
        }
    }
    
    /**
     * @notice Calculate minimum yield improvement needed to justify rebalancing
     * @param principal Principal amount
     * @param rebalanceCosts Total rebalancing costs
     * @param duration Investment duration
     * @return minImprovement Minimum APY improvement needed (basis points)
     */
    function calculateMinimumYieldImprovement(
        uint256 principal,
        uint256 rebalanceCosts,
        uint256 duration
    ) internal pure returns (uint256 minImprovement) {
        if (principal == 0 || duration == 0) return type(uint256).max;
        
        // Required improvement to cover costs over the duration
        minImprovement = (rebalanceCosts * SECONDS_PER_YEAR * BASIS_POINTS) / 
                        (principal * duration);
    }
    
    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN CALCULATIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calculate cross-chain yield opportunity
     * @param localYield Local chain yield data
     * @param remoteYield Remote chain yield data
     * @param bridgeCosts Cross-chain bridge costs
     * @param bridgeTime Time required for bridging
     * @return isWorthwhile Whether cross-chain opportunity is profitable
     * @return netBenefit Net benefit after bridge costs
     */
    function calculateCrossChainOpportunity(
        YieldData memory localYield,
        YieldData memory remoteYield,
        uint256 bridgeCosts,
        uint256 bridgeTime
    ) internal pure returns (bool isWorthwhile, uint256 netBenefit) {
        // Adjust remote yield duration for bridge time
        YieldData memory adjustedRemoteYield = remoteYield;
        adjustedRemoteYield.duration = remoteYield.duration > bridgeTime ? 
            remoteYield.duration - bridgeTime : 0;
        
        (uint256 localNetYield,) = calculateNetYield(localYield);
        (uint256 remoteNetYield,) = calculateNetYield(adjustedRemoteYield);
        
        // Account for bridge costs
        remoteNetYield = remoteNetYield > bridgeCosts ? remoteNetYield - bridgeCosts : 0;
        
        if (remoteNetYield > localNetYield) {
            netBenefit = remoteNetYield - localNetYield;
            isWorthwhile = netBenefit > 0;
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        OPTIMIZATION UTILITIES
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calculate optimal allocation across multiple protocols
     * @param protocolYields Array of protocol yield rates (basis points)
     * @param protocolRisks Array of protocol risk scores (basis points)
     * @param riskTolerance User risk tolerance (basis points)
     * @param totalAmount Total amount to allocate
     * @return allocations Optimal allocation amounts
     */
    function calculateOptimalAllocation(
        uint256[] memory protocolYields,
        uint256[] memory protocolRisks,
        uint256 riskTolerance,
        uint256 totalAmount
    ) internal pure returns (uint256[] memory allocations) {
        require(protocolYields.length == protocolRisks.length, "Array length mismatch");
        
        allocations = new uint256[](protocolYields.length);
        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](protocolYields.length);
        
        // Calculate risk-adjusted weights
        for (uint256 i = 0; i < protocolYields.length; i++) {
            if (protocolRisks[i] <= riskTolerance) {
                // Weight = yield / (1 + risk_penalty)
                uint256 riskPenalty = (protocolRisks[i] * protocolRisks[i]) / BASIS_POINTS;
                weights[i] = (protocolYields[i] * BASIS_POINTS) / (BASIS_POINTS + riskPenalty);
                totalWeight += weights[i];
            }
        }
        
        // Calculate allocations based on weights
        if (totalWeight > 0) {
            for (uint256 i = 0; i < allocations.length; i++) {
                allocations[i] = (totalAmount * weights[i]) / totalWeight;
            }
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL UTILITIES
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calculate power function with precision
     * @param base Base value
     * @param exponent Exponent value
     * @param precision Precision factor
     * @return result Base^exponent with precision
     */
    function _power(uint256 base, uint256 exponent, uint256 precision)
        private pure returns (uint256 result)
    {
        result = precision;
        uint256 basePower = base;
        
        while (exponent > 0) {
            if (exponent % 2 == 1) {
                result = (result * basePower) / precision;
            }
            basePower = (basePower * basePower) / precision;
            exponent = exponent / 2;
        }
    }
    
    /**
     * @notice Calculate square root using Newton's method
     * @param x Input value
     * @return sqrt Square root of x
     */
    function _sqrt(uint256 x) private pure returns (uint256 sqrt) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        sqrt = x;
        while (z < sqrt) {
            sqrt = z;
            z = (x / z + z) / 2;
        }
    }
}