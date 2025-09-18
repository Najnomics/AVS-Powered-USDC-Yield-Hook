// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IYieldOracle} from "../interfaces/IYieldOracle.sol";

/**
 * @title ChainlinkYieldOracle
 * @notice Chainlink-based yield rate oracle implementation
 * @dev Provides yield rate data for various DeFi protocols using Chainlink feeds
 */
contract ChainlinkYieldOracle is IYieldOracle {
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidPriceFeed();
    error StaleRate();
    error InvalidRate();
    error PriceFeedNotSet();
    error UnsupportedProtocol();
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PriceFeedUpdated(bytes32 indexed protocolId, address indexed oldFeed, address indexed newFeed);
    event MaxRateAgeUpdated(uint256 oldAge, uint256 newAge);
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Maximum acceptable rate age (1 hour)
    uint256 public constant MAX_RATE_AGE = 1 hours;
    
    /// @notice Minimum acceptable yield rate (0.01% APY)
    uint256 public constant MIN_RATE = 0.01e8; // 8 decimals
    
    /// @notice Maximum acceptable yield rate (1000% APY)
    uint256 public constant MAX_RATE = 1000e8; // 8 decimals
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Mapping from protocol ID to Chainlink price feed
    mapping(bytes32 => AggregatorV3Interface) public protocolFeeds;
    
    /// @notice Set of supported protocol IDs
    mapping(bytes32 => bool) public supportedProtocols;
    
    /// @notice Array of all supported protocol IDs
    bytes32[] public protocolIds;
    
    /// @notice Maximum acceptable rate age
    uint256 public maxRateAge;
    
    /// @notice Oracle owner (for configuration)
    address public owner;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(uint256 _maxRateAge) {
        maxRateAge = _maxRateAge;
        owner = msg.sender;
    }
    
    /*//////////////////////////////////////////////////////////////
                            YIELD FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the latest yield rate for a protocol
     * @param protocolId The protocol identifier
     * @return rate Yield rate in basis points (8 decimals)
     * @return timestamp When the rate was last updated
     */
    function getLatestYieldRate(bytes32 protocolId) external view override returns (uint256 rate, uint256 timestamp) {
        if (!supportedProtocols[protocolId]) revert UnsupportedProtocol();
        
        AggregatorV3Interface feed = protocolFeeds[protocolId];
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        
        // Validate the rate data
        if (answer <= 0) revert InvalidRate();
        if (updatedAt == 0) revert StaleRate();
        if (answeredInRound < roundId) revert StaleRate();
        
        // Check if rate is within acceptable range
        uint256 rateValue = uint256(answer);
        if (rateValue < MIN_RATE || rateValue > MAX_RATE) {
            revert InvalidRate();
        }
        
        // Check if rate is not too old
        if (block.timestamp - updatedAt > maxRateAge) {
            revert StaleRate();
        }
        
        return (rateValue, updatedAt);
    }
    
    /**
     * @notice Get yield rate for a protocol at a specific round
     * @param protocolId The protocol identifier
     * @param roundId The round ID to query
     * @return rate Yield rate in basis points (8 decimals)
     * @return timestamp When the rate was updated
     */
    function getYieldRateAtRound(bytes32 protocolId, uint80 roundId) external view override returns (uint256 rate, uint256 timestamp) {
        if (!supportedProtocols[protocolId]) revert UnsupportedProtocol();
        
        AggregatorV3Interface feed = protocolFeeds[protocolId];
        (
            uint80 id,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.getRoundData(roundId);
        
        // Validate the rate data
        if (answer <= 0) revert InvalidRate();
        if (updatedAt == 0) revert StaleRate();
        if (answeredInRound < id) revert StaleRate();
        
        // Check if rate is within acceptable range
        uint256 rateValue = uint256(answer);
        if (rateValue < MIN_RATE || rateValue > MAX_RATE) {
            revert InvalidRate();
        }
        
        return (rateValue, updatedAt);
    }
    
    /**
     * @notice Get yield rates for multiple protocols
     * @param _protocolIds Array of protocol identifiers
     * @return rates Array of yield rates
     * @return timestamps Array of timestamps
     */
    function getBatchYieldRates(bytes32[] calldata _protocolIds) external view override returns (uint256[] memory rates, uint256[] memory timestamps) {
        uint256 length = _protocolIds.length;
        rates = new uint256[](length);
        timestamps = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            if (supportedProtocols[_protocolIds[i]]) {
                (rates[i], timestamps[i]) = this.getLatestYieldRate(_protocolIds[i]);
            } else {
                rates[i] = 0;
                timestamps[i] = 0;
            }
        }
        
        return (rates, timestamps);
    }
    
    /**
     * @notice Get all supported protocol IDs
     * @return protocols Array of supported protocol IDs
     */
    function getSupportedProtocols() external view override returns (bytes32[] memory protocols) {
        return protocolIds;
    }
    
    /**
     * @notice Check if a protocol is supported
     * @param protocolId The protocol identifier
     * @return supported True if protocol is supported
     */
    function isProtocolSupported(bytes32 protocolId) external view override returns (bool supported) {
        return supportedProtocols[protocolId];
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Add a new protocol with its Chainlink price feed
     * @param protocolId The protocol identifier
     * @param priceFeed The Chainlink price feed address
     */
    function addProtocol(bytes32 protocolId, address priceFeed) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (priceFeed == address(0)) revert InvalidPriceFeed();
        if (supportedProtocols[protocolId]) revert("Protocol already exists");
        
        // Validate the price feed
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        _validatePriceFeed(feed);
        
        protocolFeeds[protocolId] = feed;
        supportedProtocols[protocolId] = true;
        protocolIds.push(protocolId);
        
        emit ProtocolAdded(protocolId, priceFeed);
    }
    
    /**
     * @notice Remove a protocol
     * @param protocolId The protocol identifier
     */
    function removeProtocol(bytes32 protocolId) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (!supportedProtocols[protocolId]) revert UnsupportedProtocol();
        
        delete protocolFeeds[protocolId];
        supportedProtocols[protocolId] = false;
        
        // Remove from protocolIds array
        for (uint256 i = 0; i < protocolIds.length; i++) {
            if (protocolIds[i] == protocolId) {
                protocolIds[i] = protocolIds[protocolIds.length - 1];
                protocolIds.pop();
                break;
            }
        }
        
        emit ProtocolRemoved(protocolId);
    }
    
    /**
     * @notice Update the price feed for a protocol
     * @param protocolId The protocol identifier
     * @param newPriceFeed The new Chainlink price feed address
     */
    function updateProtocolFeed(bytes32 protocolId, address newPriceFeed) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (!supportedProtocols[protocolId]) revert UnsupportedProtocol();
        if (newPriceFeed == address(0)) revert InvalidPriceFeed();
        
        // Validate the new price feed
        AggregatorV3Interface feed = AggregatorV3Interface(newPriceFeed);
        _validatePriceFeed(feed);
        
        address oldFeed = address(protocolFeeds[protocolId]);
        protocolFeeds[protocolId] = feed;
        
        emit PriceFeedUpdated(protocolId, oldFeed, newPriceFeed);
    }
    
    /**
     * @notice Update the maximum acceptable rate age
     * @param _maxRateAge New maximum rate age
     */
    function setMaxRateAge(uint256 _maxRateAge) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (_maxRateAge == 0 || _maxRateAge > MAX_RATE_AGE) revert InvalidRate();
        
        uint256 oldAge = maxRateAge;
        maxRateAge = _maxRateAge;
        
        emit MaxRateAgeUpdated(oldAge, _maxRateAge);
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
     * @param feed The price feed to validate
     */
    function _validatePriceFeed(AggregatorV3Interface feed) internal view {
        try feed.latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (answer <= 0) revert InvalidRate();
            if (updatedAt == 0) revert StaleRate();
        } catch {
            revert InvalidPriceFeed();
        }
    }
}
