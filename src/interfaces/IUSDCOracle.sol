// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IUSDCOracle
 * @notice Interface for USDC price oracles
 * @dev Provides standardized interface for USDC price data
 */
interface IUSDCOracle {
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PriceUpdated(uint256 price, uint256 timestamp);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    
    /*//////////////////////////////////////////////////////////////
                            PRICE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the latest USDC price in USD
     * @return price USDC price in USD (8 decimals)
     * @return timestamp When the price was last updated
     */
    function getLatestPrice() external view returns (uint256 price, uint256 timestamp);
    
    /**
     * @notice Get USDC price at a specific round
     * @param roundId The round ID to query
     * @return price USDC price in USD (8 decimals)
     * @return timestamp When the price was updated
     */
    function getPriceAtRound(uint80 roundId) external view returns (uint256 price, uint256 timestamp);
    
    /**
     * @notice Get the latest round ID
     * @return roundId The latest round ID
     */
    function getLatestRoundId() external view returns (uint80 roundId);
    
    /**
     * @notice Get round data for a specific round
     * @param roundId The round ID to query
     * @return roundId_ The round ID
     * @return answer The price answer
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round that answered
     */
    function getRoundData(uint80 roundId) external view returns (
        uint80 roundId_,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    
    /**
     * @notice Get the number of decimals for the price feed
     * @return decimals Number of decimals
     */
    function decimals() external view returns (uint8);
    
    /**
     * @notice Get the description of the price feed
     * @return description Price feed description
     */
    function description() external view returns (string memory);
    
    /**
     * @notice Get the version of the price feed
     * @return version Price feed version
     */
    function version() external view returns (uint256);
}

