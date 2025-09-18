// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUSDCOracle} from "../interfaces/IUSDCOracle.sol";

/**
 * @title ChainlinkUSDCOracle
 * @notice Chainlink-based USDC price oracle implementation
 * @dev Provides USDC/USD price data using Chainlink price feeds
 */
contract ChainlinkUSDCOracle is IUSDCOracle {
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidPriceFeed();
    error StalePrice();
    error InvalidPrice();
    error PriceFeedNotSet();
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event MaxPriceAgeUpdated(uint256 oldAge, uint256 newAge);
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Maximum acceptable price age (24 hours)
    uint256 public constant MAX_PRICE_AGE = 24 hours;
    
    /// @notice Minimum acceptable price (0.01 USD)
    uint256 public constant MIN_PRICE = 0.01e8; // 8 decimals
    
    /// @notice Maximum acceptable price (1000 USD)
    uint256 public constant MAX_PRICE = 1000e8; // 8 decimals
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Chainlink price feed for USDC/USD
    AggregatorV3Interface public immutable priceFeed;
    
    /// @notice Maximum acceptable price age
    uint256 public maxPriceAge;
    
    /// @notice Oracle owner (for configuration)
    address public owner;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address _priceFeed, uint256 _maxPriceAge) {
        if (_priceFeed == address(0)) revert InvalidPriceFeed();
        
        priceFeed = AggregatorV3Interface(_priceFeed);
        maxPriceAge = _maxPriceAge;
        owner = msg.sender;
        
        // Verify the price feed is working
        _validatePriceFeed();
    }
    
    /*//////////////////////////////////////////////////////////////
                            PRICE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the latest USDC price in USD
     * @return price USDC price in USD (8 decimals)
     * @return timestamp When the price was last updated
     */
    function getLatestPrice() external view override returns (uint256 price, uint256 timestamp) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        
        // Validate the price data
        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0) revert StalePrice();
        if (answeredInRound < roundId) revert StalePrice();
        
        // Check if price is within acceptable range
        uint256 priceValue = uint256(answer);
        if (priceValue < MIN_PRICE || priceValue > MAX_PRICE) {
            revert InvalidPrice();
        }
        
        // Check if price is not too old
        if (block.timestamp - updatedAt > maxPriceAge) {
            revert StalePrice();
        }
        
        return (priceValue, updatedAt);
    }
    
    /**
     * @notice Get USDC price at a specific round
     * @param roundId The round ID to query
     * @return price USDC price in USD (8 decimals)
     * @return timestamp When the price was updated
     */
    function getPriceAtRound(uint80 roundId) external view override returns (uint256 price, uint256 timestamp) {
        (
            uint80 id,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.getRoundData(roundId);
        
        // Validate the price data
        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0) revert StalePrice();
        if (answeredInRound < id) revert StalePrice();
        
        // Check if price is within acceptable range
        uint256 priceValue = uint256(answer);
        if (priceValue < MIN_PRICE || priceValue > MAX_PRICE) {
            revert InvalidPrice();
        }
        
        return (priceValue, updatedAt);
    }
    
    /**
     * @notice Get the latest round ID
     * @return roundId The latest round ID
     */
    function getLatestRoundId() external view override returns (uint80 roundId) {
        (roundId,,,,) = priceFeed.latestRoundData();
        return roundId;
    }
    
    /**
     * @notice Get round data for a specific round
     * @param roundId The round ID to query
     * @return roundId_ The round ID
     * @return answer The price answer
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round that answered
     */
    function getRoundData(uint80 roundId) external view override returns (
        uint80 roundId_,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return priceFeed.getRoundData(roundId);
    }
    
    /**
     * @notice Get the number of decimals for the price feed
     * @return decimals Number of decimals
     */
    function decimals() external view override returns (uint8) {
        return priceFeed.decimals();
    }
    
    /**
     * @notice Get the description of the price feed
     * @return description Price feed description
     */
    function description() external view override returns (string memory) {
        return priceFeed.description();
    }
    
    /**
     * @notice Get the version of the price feed
     * @return version Price feed version
     */
    function version() external view override returns (uint256) {
        return priceFeed.version();
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update the maximum acceptable price age
     * @param _maxPriceAge New maximum price age
     */
    function setMaxPriceAge(uint256 _maxPriceAge) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (_maxPriceAge == 0 || _maxPriceAge > MAX_PRICE_AGE) revert InvalidPrice();
        
        uint256 oldAge = maxPriceAge;
        maxPriceAge = _maxPriceAge;
        
        emit MaxPriceAgeUpdated(oldAge, _maxPriceAge);
    }
    
    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (newOwner == address(0)) revert("Invalid owner");
        
        owner = newOwner;
    }
    
    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Validate that the price feed is working correctly
     */
    function _validatePriceFeed() internal view {
        try priceFeed.latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (answer <= 0) revert InvalidPrice();
            if (updatedAt == 0) revert StalePrice();
        } catch {
            revert InvalidPriceFeed();
        }
    }
}
