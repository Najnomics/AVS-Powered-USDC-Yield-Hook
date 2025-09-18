// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {OracleAggregator} from "../../src/oracles/OracleAggregator.sol";
import {ChainlinkUSDCOracle} from "../../src/oracles/ChainlinkUSDCOracle.sol";
import {ChainlinkYieldOracle} from "../../src/oracles/ChainlinkYieldOracle.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

/**
 * @title OracleAggregatorUnitTest
 * @notice Comprehensive unit tests for OracleAggregator
 * @dev Tests all functions, edge cases, and error conditions
 */
contract OracleAggregatorUnitTest is Test {
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    OracleAggregator public aggregator;
    ChainlinkUSDCOracle public usdcOracle;
    ChainlinkYieldOracle public yieldOracle;
    ChainlinkUSDCOracle public fallbackUSDCOracle;
    ChainlinkYieldOracle public fallbackYieldOracle;
    
    MockV3Aggregator public mockUSDCFeed;
    MockV3Aggregator public mockYieldFeed;
    MockV3Aggregator public mockFallbackUSDCFeed;
    MockV3Aggregator public mockFallbackYieldFeed;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant OWNER = address(0x1);
    address constant NEW_OWNER = address(0x2);
    
    uint256 constant USDC_PRICE = 1e8; // $1.00 (8 decimals)
    uint256 constant YIELD_RATE = 500e6; // 5% APY (8 decimals)
    uint256 constant MAX_DATA_AGE = 1 hours;
    
    bytes32 constant AAVE_PROTOCOL = keccak256("AAVE_V3");
    bytes32 constant COMPOUND_PROTOCOL = keccak256("COMPOUND_V3");
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Deploy mock price feeds
        mockUSDCFeed = new MockV3Aggregator(8, int256(USDC_PRICE), 1, 1, block.timestamp, 1);
        mockYieldFeed = new MockV3Aggregator(8, int256(YIELD_RATE), 1, 1, block.timestamp, 1);
        mockFallbackUSDCFeed = new MockV3Aggregator(8, int256(USDC_PRICE), 1, 1, block.timestamp, 1);
        mockFallbackYieldFeed = new MockV3Aggregator(8, int256(YIELD_RATE), 1, 1, block.timestamp, 1);
        
        // Deploy oracles
        usdcOracle = new ChainlinkUSDCOracle(address(mockUSDCFeed), 24 hours);
        yieldOracle = new ChainlinkYieldOracle(1 hours);
        fallbackUSDCOracle = new ChainlinkUSDCOracle(address(mockFallbackUSDCFeed), 24 hours);
        fallbackYieldOracle = new ChainlinkYieldOracle(1 hours);
        
        // Add protocols to yield oracle
        yieldOracle.addProtocol(AAVE_PROTOCOL, address(mockYieldFeed));
        fallbackYieldOracle.addProtocol(AAVE_PROTOCOL, address(mockFallbackYieldFeed));
        
        // Deploy aggregator
        aggregator = new OracleAggregator(
            address(usdcOracle),
            address(yieldOracle),
            MAX_DATA_AGE
        );
        
        // Transfer ownership to test contract
        aggregator.transferOwnership(OWNER);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(address(aggregator.usdcOracle()), address(usdcOracle));
        assertEq(address(aggregator.yieldOracle()), address(yieldOracle));
        assertEq(aggregator.maxDataAge(), MAX_DATA_AGE);
        assertEq(aggregator.owner(), OWNER);
    }
    
    function test_Constructor_RevertWhen_ZeroUSDCOracle() public {
        vm.expectRevert(OracleAggregator.InvalidOracle.selector);
        new OracleAggregator(
            address(0),
            address(yieldOracle),
            MAX_DATA_AGE
        );
    }
    
    function test_Constructor_RevertWhen_ZeroYieldOracle() public {
        vm.expectRevert(OracleAggregator.InvalidOracle.selector);
        new OracleAggregator(
            address(usdcOracle),
            address(0),
            MAX_DATA_AGE
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            USDC PRICE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestUSDCPrice() public {
        (uint256 price, uint256 timestamp, address oracleAddress) = aggregator.getLatestUSDCPrice();
        
        assertEq(price, USDC_PRICE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(usdcOracle));
    }
    
    function test_GetLatestUSDCPrice_WithFallback() public {
        // Make primary oracle fail
        mockUSDCFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        // Add fallback oracle
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
        
        (uint256 price, uint256 timestamp, address oracleAddress) = aggregator.getLatestUSDCPrice();
        
        assertEq(price, USDC_PRICE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(fallbackUSDCOracle));
    }
    
    function test_GetLatestUSDCPrice_RevertWhen_NoValidOracle() public {
        // Make primary oracle fail
        mockUSDCFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        vm.expectRevert(OracleAggregator.NoValidOracle.selector);
        aggregator.getLatestUSDCPrice();
    }
    
    function test_GetUSDCPriceAtRound() public {
        (uint256 price, uint256 timestamp, address oracleAddress) = aggregator.getUSDCPriceAtRound(1);
        
        assertEq(price, USDC_PRICE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(usdcOracle));
    }
    
    function test_GetUSDCPriceAtRound_WithFallback() public {
        // Make primary oracle fail
        mockUSDCFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        // Add fallback oracle
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
        
        (uint256 price, uint256 timestamp, address oracleAddress) = aggregator.getUSDCPriceAtRound(1);
        
        assertEq(price, USDC_PRICE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(fallbackUSDCOracle));
    }
    
    function test_GetUSDCPriceAtRound_RevertWhen_NoValidOracle() public {
        // Make primary oracle fail
        mockUSDCFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        vm.expectRevert(OracleAggregator.NoValidOracle.selector);
        aggregator.getUSDCPriceAtRound(1);
    }
    
    /*//////////////////////////////////////////////////////////////
                            YIELD RATE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestYieldRate() public {
        (uint256 rate, uint256 timestamp, address oracleAddress) = aggregator.getLatestYieldRate(AAVE_PROTOCOL);
        
        assertEq(rate, YIELD_RATE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(yieldOracle));
    }
    
    function test_GetLatestYieldRate_WithFallback() public {
        // Make primary oracle fail
        mockYieldFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        // Add fallback oracle
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
        
        (uint256 rate, uint256 timestamp, address oracleAddress) = aggregator.getLatestYieldRate(AAVE_PROTOCOL);
        
        assertEq(rate, YIELD_RATE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(fallbackYieldOracle));
    }
    
    function test_GetLatestYieldRate_RevertWhen_NoValidOracle() public {
        // Make primary oracle fail
        mockYieldFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        vm.expectRevert(OracleAggregator.NoValidOracle.selector);
        aggregator.getLatestYieldRate(AAVE_PROTOCOL);
    }
    
    function test_GetBatchYieldRates() public {
        bytes32[] memory protocolIds = new bytes32[](1);
        protocolIds[0] = AAVE_PROTOCOL;
        
        (uint256[] memory rates, uint256[] memory timestamps, address[] memory oracleAddresses) = 
            aggregator.getBatchYieldRates(protocolIds);
        
        assertEq(rates.length, 1);
        assertEq(timestamps.length, 1);
        assertEq(oracleAddresses.length, 1);
        assertEq(rates[0], YIELD_RATE);
        assertTrue(timestamps[0] > 0);
        assertEq(oracleAddresses[0], address(yieldOracle));
    }
    
    function test_GetBatchYieldRates_WithFallback() public {
        // Make primary oracle fail
        mockYieldFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        // Add fallback oracle
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
        
        bytes32[] memory protocolIds = new bytes32[](1);
        protocolIds[0] = AAVE_PROTOCOL;
        
        (uint256[] memory rates, uint256[] memory timestamps, address[] memory oracleAddresses) = 
            aggregator.getBatchYieldRates(protocolIds);
        
        assertEq(rates.length, 1);
        assertEq(timestamps.length, 1);
        assertEq(oracleAddresses.length, 1);
        assertEq(rates[0], YIELD_RATE);
        assertTrue(timestamps[0] > 0);
        assertEq(oracleAddresses[0], address(fallbackYieldOracle));
    }
    
    function test_GetSupportedProtocols() public {
        bytes32[] memory protocols = aggregator.getSupportedProtocols();
        assertEq(protocols.length, 1);
        assertEq(protocols[0], AAVE_PROTOCOL);
    }
    
    function test_IsProtocolSupported() public {
        assertTrue(aggregator.isProtocolSupported(AAVE_PROTOCOL));
        assertFalse(aggregator.isProtocolSupported(keccak256("UNSUPPORTED")));
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetUSDCOracle() public {
        vm.prank(OWNER);
        aggregator.setUSDCOracle(address(fallbackUSDCOracle));
        
        assertEq(address(aggregator.usdcOracle()), address(fallbackUSDCOracle));
    }
    
    function test_SetUSDCOracle_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        aggregator.setUSDCOracle(address(fallbackUSDCOracle));
    }
    
    function test_SetUSDCOracle_RevertWhen_ZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(OracleAggregator.InvalidOracle.selector);
        aggregator.setUSDCOracle(address(0));
    }
    
    function test_SetYieldOracle() public {
        vm.prank(OWNER);
        aggregator.setYieldOracle(address(fallbackYieldOracle));
        
        assertEq(address(aggregator.yieldOracle()), address(fallbackYieldOracle));
    }
    
    function test_SetYieldOracle_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        aggregator.setYieldOracle(address(fallbackYieldOracle));
    }
    
    function test_SetYieldOracle_RevertWhen_ZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(OracleAggregator.InvalidOracle.selector);
        aggregator.setYieldOracle(address(0));
    }
    
    function test_AddFallbackUSDCOracle() public {
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
        
        assertEq(address(aggregator.fallbackUSDCOracles(0)), address(fallbackUSDCOracle));
    }
    
    function test_AddFallbackUSDCOracle_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
    }
    
    function test_AddFallbackUSDCOracle_RevertWhen_ZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(OracleAggregator.InvalidOracle.selector);
        aggregator.addFallbackUSDCOracle(address(0));
    }
    
    function test_AddFallbackYieldOracle() public {
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
        
        assertEq(address(aggregator.fallbackYieldOracles(0)), address(fallbackYieldOracle));
    }
    
    function test_AddFallbackYieldOracle_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
    }
    
    function test_AddFallbackYieldOracle_RevertWhen_ZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(OracleAggregator.InvalidOracle.selector);
        aggregator.addFallbackYieldOracle(address(0));
    }
    
    function test_RemoveFallbackUSDCOracle() public {
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
        
        vm.prank(OWNER);
        aggregator.removeFallbackUSDCOracle(0);
        
        // Should be empty now
        assertEq(aggregator.fallbackUSDCOracles(0), address(0));
    }
    
    function test_RemoveFallbackUSDCOracle_RevertWhen_NotOwner() public {
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
        
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        aggregator.removeFallbackUSDCOracle(0);
    }
    
    function test_RemoveFallbackUSDCOracle_RevertWhen_InvalidIndex() public {
        vm.prank(OWNER);
        vm.expectRevert("Invalid index");
        aggregator.removeFallbackUSDCOracle(0);
    }
    
    function test_RemoveFallbackYieldOracle() public {
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
        
        vm.prank(OWNER);
        aggregator.removeFallbackYieldOracle(0);
        
        // Should be empty now
        assertEq(aggregator.fallbackYieldOracles(0), address(0));
    }
    
    function test_RemoveFallbackYieldOracle_RevertWhen_NotOwner() public {
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
        
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        aggregator.removeFallbackYieldOracle(0);
    }
    
    function test_RemoveFallbackYieldOracle_RevertWhen_InvalidIndex() public {
        vm.prank(OWNER);
        vm.expectRevert("Invalid index");
        aggregator.removeFallbackYieldOracle(0);
    }
    
    function test_SetMaxDataAge() public {
        uint256 newMaxAge = 30 minutes;
        
        vm.prank(OWNER);
        aggregator.setMaxDataAge(newMaxAge);
        
        assertEq(aggregator.maxDataAge(), newMaxAge);
    }
    
    function test_SetMaxDataAge_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        aggregator.setMaxDataAge(30 minutes);
    }
    
    function test_SetMaxDataAge_RevertWhen_ZeroAge() public {
        vm.prank(OWNER);
        vm.expectRevert(OracleAggregator.InvalidData.selector);
        aggregator.setMaxDataAge(0);
    }
    
    function test_TransferOwnership() public {
        vm.prank(OWNER);
        aggregator.transferOwnership(NEW_OWNER);
        
        assertEq(aggregator.owner(), NEW_OWNER);
    }
    
    function test_TransferOwnership_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        aggregator.transferOwnership(NEW_OWNER);
    }
    
    function test_TransferOwnership_RevertWhen_ZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert("Invalid owner");
        aggregator.transferOwnership(address(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestUSDCPrice_MultipleFallbacks() public {
        // Make primary oracle fail
        mockUSDCFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        // Add multiple fallback oracles
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
        
        // Add another fallback that will fail
        ChainlinkUSDCOracle anotherFallback = new ChainlinkUSDCOracle(
            address(mockFallbackUSDCFeed),
            24 hours
        );
        MockV3Aggregator anotherFeed = new MockV3Aggregator(8, -1, 1, 1, block.timestamp, 1);
        anotherFallback.addProtocol(AAVE_PROTOCOL, address(anotherFeed));
        
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(anotherFallback));
        
        (uint256 price, uint256 timestamp, address oracleAddress) = aggregator.getLatestUSDCPrice();
        
        assertEq(price, USDC_PRICE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(fallbackUSDCOracle));
    }
    
    function test_GetLatestYieldRate_MultipleFallbacks() public {
        // Make primary oracle fail
        mockYieldFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        // Add multiple fallback oracles
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
        
        (uint256 rate, uint256 timestamp, address oracleAddress) = aggregator.getLatestYieldRate(AAVE_PROTOCOL);
        
        assertEq(rate, YIELD_RATE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(fallbackYieldOracle));
    }
    
    function test_GetBatchYieldRates_MixedResults() public {
        // Add a protocol that will fail
        yieldOracle.addProtocol(COMPOUND_PROTOCOL, address(mockYieldFeed));
        mockYieldFeed.updateRoundData(2, -1, block.timestamp, 2);
        
        bytes32[] memory protocolIds = new bytes32[](2);
        protocolIds[0] = AAVE_PROTOCOL;
        protocolIds[1] = COMPOUND_PROTOCOL;
        
        (uint256[] memory rates, uint256[] memory timestamps, address[] memory oracleAddresses) = 
            aggregator.getBatchYieldRates(protocolIds);
        
        assertEq(rates.length, 2);
        assertEq(timestamps.length, 2);
        assertEq(oracleAddresses.length, 2);
        assertEq(rates[0], YIELD_RATE); // AAVE should work
        assertEq(rates[1], 0); // COMPOUND should fail
        assertTrue(timestamps[0] > 0);
        assertEq(timestamps[1], 0);
        assertEq(oracleAddresses[0], address(yieldOracle));
        assertEq(oracleAddresses[1], address(0));
    }
    
    function test_RemoveFallbackUSDCOracle_UpdatesArray() public {
        // Add multiple fallbacks
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
        
        ChainlinkUSDCOracle anotherFallback = new ChainlinkUSDCOracle(
            address(mockFallbackUSDCFeed),
            24 hours
        );
        
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(anotherFallback));
        
        // Remove first one
        vm.prank(OWNER);
        aggregator.removeFallbackUSDCOracle(0);
        
        // Second one should now be at index 0
        assertEq(address(aggregator.fallbackUSDCOracles(0)), address(anotherFallback));
    }
    
    function test_RemoveFallbackYieldOracle_UpdatesArray() public {
        // Add multiple fallbacks
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
        
        ChainlinkYieldOracle anotherFallback = new ChainlinkYieldOracle(1 hours);
        anotherFallback.addProtocol(AAVE_PROTOCOL, address(mockFallbackYieldFeed));
        
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(anotherFallback));
        
        // Remove first one
        vm.prank(OWNER);
        aggregator.removeFallbackYieldOracle(0);
        
        // Second one should now be at index 0
        assertEq(address(aggregator.fallbackYieldOracles(0)), address(anotherFallback));
    }
    
    /*//////////////////////////////////////////////////////////////
                            EVENTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetUSDCOracle_Event() public {
        vm.expectEmit(true, true, true, true);
        emit OracleAggregator.USDCOracleUpdated(address(usdcOracle), address(fallbackUSDCOracle));
        
        vm.prank(OWNER);
        aggregator.setUSDCOracle(address(fallbackUSDCOracle));
    }
    
    function test_SetYieldOracle_Event() public {
        vm.expectEmit(true, true, true, true);
        emit OracleAggregator.YieldOracleUpdated(address(yieldOracle), address(fallbackYieldOracle));
        
        vm.prank(OWNER);
        aggregator.setYieldOracle(address(fallbackYieldOracle));
    }
    
    function test_AddFallbackUSDCOracle_Event() public {
        vm.expectEmit(true, true, true, true);
        emit OracleAggregator.FallbackOracleAdded(address(fallbackUSDCOracle), 0);
        
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
    }
    
    function test_AddFallbackYieldOracle_Event() public {
        vm.expectEmit(true, true, true, true);
        emit OracleAggregator.FallbackOracleAdded(address(fallbackYieldOracle), 0);
        
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
    }
    
    function test_RemoveFallbackUSDCOracle_Event() public {
        vm.prank(OWNER);
        aggregator.addFallbackUSDCOracle(address(fallbackUSDCOracle));
        
        vm.expectEmit(true, true, true, true);
        emit OracleAggregator.FallbackOracleRemoved(address(fallbackUSDCOracle), 0);
        
        vm.prank(OWNER);
        aggregator.removeFallbackUSDCOracle(0);
    }
    
    function test_RemoveFallbackYieldOracle_Event() public {
        vm.prank(OWNER);
        aggregator.addFallbackYieldOracle(address(fallbackYieldOracle));
        
        vm.expectEmit(true, true, true, true);
        emit OracleAggregator.FallbackOracleRemoved(address(fallbackYieldOracle), 0);
        
        vm.prank(OWNER);
        aggregator.removeFallbackYieldOracle(0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_GetLatestUSDCPrice_ValidPrice(uint256 price) public {
        // Bound price to valid range
        price = bound(price, 0.01e8, 1000e8);
        
        mockUSDCFeed.updateRoundData(2, int256(price), block.timestamp, 2);
        
        (uint256 returnedPrice, uint256 timestamp, address oracleAddress) = aggregator.getLatestUSDCPrice();
        
        assertEq(returnedPrice, price);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(usdcOracle));
    }
    
    function testFuzz_GetLatestYieldRate_ValidRate(uint256 rate) public {
        // Bound rate to valid range
        rate = bound(rate, 0.01e8, 1000e8);
        
        mockYieldFeed.updateRoundData(2, int256(rate), block.timestamp, 2);
        
        (uint256 returnedRate, uint256 timestamp, address oracleAddress) = aggregator.getLatestYieldRate(AAVE_PROTOCOL);
        
        assertEq(returnedRate, rate);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(yieldOracle));
    }
    
    function testFuzz_SetMaxDataAge_ValidAge(uint256 age) public {
        age = bound(age, 1, 24 hours);
        
        vm.prank(OWNER);
        aggregator.setMaxDataAge(age);
        
        assertEq(aggregator.maxDataAge(), age);
    }
}
