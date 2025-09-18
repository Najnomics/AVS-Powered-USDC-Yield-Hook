// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IYieldOracle
 * @notice Interface for yield rate oracles
 * @dev Provides standardized interface for yield rate data across protocols
 */
interface IYieldOracle {
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event YieldRateUpdated(bytes32 indexed protocolId, uint256 rate, uint256 timestamp);
    event ProtocolAdded(bytes32 indexed protocolId, address indexed priceFeed);
    event ProtocolRemoved(bytes32 indexed protocolId);
    
    /*//////////////////////////////////////////////////////////////
                            YIELD FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the latest yield rate for a protocol
     * @param protocolId The protocol identifier
     * @return rate Yield rate in basis points (8 decimals)
     * @return timestamp When the rate was last updated
     */
    function getLatestYieldRate(bytes32 protocolId) external view returns (uint256 rate, uint256 timestamp);
    
    /**
     * @notice Get yield rate for a protocol at a specific round
     * @param protocolId The protocol identifier
     * @param roundId The round ID to query
     * @return rate Yield rate in basis points (8 decimals)
     * @return timestamp When the rate was updated
     */
    function getYieldRateAtRound(bytes32 protocolId, uint80 roundId) external view returns (uint256 rate, uint256 timestamp);
    
    /**
     * @notice Get yield rates for multiple protocols
     * @param protocolIds Array of protocol identifiers
     * @return rates Array of yield rates
     * @return timestamps Array of timestamps
     */
    function getBatchYieldRates(bytes32[] calldata protocolIds) external view returns (uint256[] memory rates, uint256[] memory timestamps);
    
    /**
     * @notice Get all supported protocol IDs
     * @return protocols Array of supported protocol IDs
     */
    function getSupportedProtocols() external view returns (bytes32[] memory protocols);
    
    /**
     * @notice Check if a protocol is supported
     * @param protocolId The protocol identifier
     * @return supported True if protocol is supported
     */
    function isProtocolSupported(bytes32 protocolId) external view returns (bool supported);
}
