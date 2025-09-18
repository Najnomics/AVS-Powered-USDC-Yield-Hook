// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IUSDCOracle} from "../interfaces/IUSDCOracle.sol";
import {IYieldOracle} from "../interfaces/IYieldOracle.sol";

/**
 * @title OracleAggregator
 * @notice Aggregates multiple oracle sources for price and yield data
 * @dev Provides fallback mechanisms and data validation across multiple oracles
 */
contract OracleAggregator {
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidOracle();
    error NoValidOracle();
    error StaleData();
    error InvalidData();
    error OracleNotSet();
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event USDCOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event YieldOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event FallbackOracleAdded(address indexed oracle, uint256 index);
    event FallbackOracleRemoved(address indexed oracle, uint256 index);
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Primary USDC price oracle
    IUSDCOracle public usdcOracle;
    
    /// @notice Primary yield rate oracle
    IYieldOracle public yieldOracle;
    
    /// @notice Fallback USDC price oracles
    IUSDCOracle[] public fallbackUSDCOracles;
    
    /// @notice Fallback yield rate oracles
    IYieldOracle[] public fallbackYieldOracles;
    
    /// @notice Maximum acceptable data age (1 hour)
    uint256 public maxDataAge;
    
    /// @notice Oracle owner
    address public owner;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address _usdcOracle,
        address _yieldOracle,
        uint256 _maxDataAge
    ) {
        if (_usdcOracle == address(0) || _yieldOracle == address(0)) revert InvalidOracle();
        
        usdcOracle = IUSDCOracle(_usdcOracle);
        yieldOracle = IYieldOracle(_yieldOracle);
        maxDataAge = _maxDataAge;
        owner = msg.sender;
    }
    
    /*//////////////////////////////////////////////////////////////
                            PRICE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the latest USDC price with fallback support
     * @return price USDC price in USD (8 decimals)
     * @return timestamp When the price was last updated
     * @return oracleAddress Address of the oracle that provided the data
     */
    function getLatestUSDCPrice() external view returns (uint256 price, uint256 timestamp, address oracleAddress) {
        // Try primary oracle first
        try usdcOracle.getLatestPrice() returns (uint256 p, uint256 t) {
            if (_isDataValid(t)) {
                return (p, t, address(usdcOracle));
            }
        } catch {}
        
        // Try fallback oracles
        for (uint256 i = 0; i < fallbackUSDCOracles.length; i++) {
            try fallbackUSDCOracles[i].getLatestPrice() returns (uint256 p, uint256 t) {
                if (_isDataValid(t)) {
                    return (p, t, address(fallbackUSDCOracles[i]));
                }
            } catch {}
        }
        
        revert NoValidOracle();
    }
    
    /**
     * @notice Get USDC price at a specific round
     * @param roundId The round ID to query
     * @return price USDC price in USD (8 decimals)
     * @return timestamp When the price was updated
     * @return oracleAddress Address of the oracle that provided the data
     */
    function getUSDCPriceAtRound(uint80 roundId) external view returns (uint256 price, uint256 timestamp, address oracleAddress) {
        // Try primary oracle first
        try usdcOracle.getPriceAtRound(roundId) returns (uint256 p, uint256 t) {
            if (_isDataValid(t)) {
                return (p, t, address(usdcOracle));
            }
        } catch {}
        
        // Try fallback oracles
        for (uint256 i = 0; i < fallbackUSDCOracles.length; i++) {
            try fallbackUSDCOracles[i].getPriceAtRound(roundId) returns (uint256 p, uint256 t) {
                if (_isDataValid(t)) {
                    return (p, t, address(fallbackUSDCOracles[i]));
                }
            } catch {}
        }
        
        revert NoValidOracle();
    }
    
    /*//////////////////////////////////////////////////////////////
                            YIELD FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the latest yield rate for a protocol with fallback support
     * @param protocolId The protocol identifier
     * @return rate Yield rate in basis points (8 decimals)
     * @return timestamp When the rate was last updated
     * @return oracleAddress Address of the oracle that provided the data
     */
    function getLatestYieldRate(bytes32 protocolId) external view returns (uint256 rate, uint256 timestamp, address oracleAddress) {
        // Try primary oracle first
        try yieldOracle.getLatestYieldRate(protocolId) returns (uint256 r, uint256 t) {
            if (_isDataValid(t)) {
                return (r, t, address(yieldOracle));
            }
        } catch {}
        
        // Try fallback oracles
        for (uint256 i = 0; i < fallbackYieldOracles.length; i++) {
            try fallbackYieldOracles[i].getLatestYieldRate(protocolId) returns (uint256 r, uint256 t) {
                if (_isDataValid(t)) {
                    return (r, t, address(fallbackYieldOracles[i]));
                }
            } catch {}
        }
        
        revert NoValidOracle();
    }
    
    /**
     * @notice Get yield rates for multiple protocols
     * @param protocolIds Array of protocol identifiers
     * @return rates Array of yield rates
     * @return timestamps Array of timestamps
     * @return oracleAddresses Array of oracle addresses
     */
    function getBatchYieldRates(bytes32[] calldata protocolIds) external view returns (
        uint256[] memory rates,
        uint256[] memory timestamps,
        address[] memory oracleAddresses
    ) {
        uint256 length = protocolIds.length;
        rates = new uint256[](length);
        timestamps = new uint256[](length);
        oracleAddresses = new address[](length);
        
        for (uint256 i = 0; i < length; i++) {
            try this.getLatestYieldRate(protocolIds[i]) returns (uint256 rate, uint256 timestamp, address oracleAddress) {
                rates[i] = rate;
                timestamps[i] = timestamp;
                oracleAddresses[i] = oracleAddress;
            } catch {
                rates[i] = 0;
                timestamps[i] = 0;
                oracleAddresses[i] = address(0);
            }
        }
        
        return (rates, timestamps, oracleAddresses);
    }
    
    /**
     * @notice Get all supported protocol IDs from the primary yield oracle
     * @return protocols Array of supported protocol IDs
     */
    function getSupportedProtocols() external view returns (bytes32[] memory protocols) {
        return yieldOracle.getSupportedProtocols();
    }
    
    /**
     * @notice Check if a protocol is supported
     * @param protocolId The protocol identifier
     * @return supported True if protocol is supported
     */
    function isProtocolSupported(bytes32 protocolId) external view returns (bool supported) {
        return yieldOracle.isProtocolSupported(protocolId);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Set the primary USDC oracle
     * @param _usdcOracle The USDC oracle address
     */
    function setUSDCOracle(address _usdcOracle) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (_usdcOracle == address(0)) revert InvalidOracle();
        
        address oldOracle = address(usdcOracle);
        usdcOracle = IUSDCOracle(_usdcOracle);
        
        emit USDCOracleUpdated(oldOracle, _usdcOracle);
    }
    
    /**
     * @notice Set the primary yield oracle
     * @param _yieldOracle The yield oracle address
     */
    function setYieldOracle(address _yieldOracle) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (_yieldOracle == address(0)) revert InvalidOracle();
        
        address oldOracle = address(yieldOracle);
        yieldOracle = IYieldOracle(_yieldOracle);
        
        emit YieldOracleUpdated(oldOracle, _yieldOracle);
    }
    
    /**
     * @notice Add a fallback USDC oracle
     * @param _oracle The USDC oracle address
     */
    function addFallbackUSDCOracle(address _oracle) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (_oracle == address(0)) revert InvalidOracle();
        
        fallbackUSDCOracles.push(IUSDCOracle(_oracle));
        
        emit FallbackOracleAdded(_oracle, fallbackUSDCOracles.length - 1);
    }
    
    /**
     * @notice Add a fallback yield oracle
     * @param _oracle The yield oracle address
     */
    function addFallbackYieldOracle(address _oracle) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (_oracle == address(0)) revert InvalidOracle();
        
        fallbackYieldOracles.push(IYieldOracle(_oracle));
        
        emit FallbackOracleAdded(_oracle, fallbackYieldOracles.length - 1);
    }
    
    /**
     * @notice Remove a fallback USDC oracle
     * @param index The index of the oracle to remove
     */
    function removeFallbackUSDCOracle(uint256 index) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (index >= fallbackUSDCOracles.length) revert("Invalid index");
        
        address oracle = address(fallbackUSDCOracles[index]);
        fallbackUSDCOracles[index] = fallbackUSDCOracles[fallbackUSDCOracles.length - 1];
        fallbackUSDCOracles.pop();
        
        emit FallbackOracleRemoved(oracle, index);
    }
    
    /**
     * @notice Remove a fallback yield oracle
     * @param index The index of the oracle to remove
     */
    function removeFallbackYieldOracle(uint256 index) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (index >= fallbackYieldOracles.length) revert("Invalid index");
        
        address oracle = address(fallbackYieldOracles[index]);
        fallbackYieldOracles[index] = fallbackYieldOracles[fallbackYieldOracles.length - 1];
        fallbackYieldOracles.pop();
        
        emit FallbackOracleRemoved(oracle, index);
    }
    
    /**
     * @notice Update the maximum acceptable data age
     * @param _maxDataAge New maximum data age
     */
    function setMaxDataAge(uint256 _maxDataAge) external {
        if (msg.sender != owner) revert("Unauthorized");
        if (_maxDataAge == 0) revert InvalidData();
        
        maxDataAge = _maxDataAge;
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
     * @notice Check if data is valid based on timestamp
     * @param timestamp The data timestamp
     * @return valid True if data is valid
     */
    function _isDataValid(uint256 timestamp) internal view returns (bool valid) {
        return timestamp > 0 && (block.timestamp - timestamp) <= maxDataAge;
    }
}
