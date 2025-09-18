// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {ChainlinkYieldOracle} from "../../src/oracles/ChainlinkYieldOracle.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

/**
 * @title ChainlinkYieldOracleUnitTest
 * @notice Comprehensive unit tests for ChainlinkYieldOracle
 * @dev Tests all functions, edge cases, and error conditions
 */
contract ChainlinkYieldOracleUnitTest is Test {
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    ChainlinkYieldOracle public oracle;
    MockV3Aggregator public mockAaveFeed;
    MockV3Aggregator public mockCompoundFeed;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant OWNER = address(0x1);
    address constant NEW_OWNER = address(0x2);
    
    uint256 constant AAVE_YIELD = 500e6; // 5% APY (8 decimals)
    uint256 constant COMPOUND_YIELD = 450e6; // 4.5% APY (8 decimals)
    uint8 constant DECIMALS = 8;
    uint256 constant MAX_RATE_AGE = 1 hours;
    
    bytes32 constant AAVE_PROTOCOL = keccak256("AAVE_V3");
    bytes32 constant COMPOUND_PROTOCOL = keccak256("COMPOUND_V3");
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Deploy mock price feeds
        mockAaveFeed = new MockV3Aggregator(
            DECIMALS,
            int256(AAVE_YIELD),
            1, // roundId
            1, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );
        
        mockCompoundFeed = new MockV3Aggregator(
            DECIMALS,
            int256(COMPOUND_YIELD),
            1,
            1,
            block.timestamp,
            1
        );
        
        // Deploy oracle
        oracle = new ChainlinkYieldOracle(MAX_RATE_AGE);
        
        // Transfer ownership to test contract
        oracle.transferOwnership(OWNER);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(oracle.maxRateAge(), MAX_RATE_AGE);
        assertEq(oracle.owner(), OWNER);
    }
    
    /*//////////////////////////////////////////////////////////////
                            PROTOCOL MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AddProtocol() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        assertTrue(oracle.isProtocolSupported(AAVE_PROTOCOL));
        assertEq(address(oracle.protocolFeeds(AAVE_PROTOCOL)), address(mockAaveFeed));
        
        bytes32[] memory protocols = oracle.getSupportedProtocols();
        assertEq(protocols.length, 1);
        assertEq(protocols[0], AAVE_PROTOCOL);
    }
    
    function test_AddProtocol_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
    }
    
    function test_AddProtocol_RevertWhen_ZeroPriceFeed() public {
        vm.prank(OWNER);
        vm.expectRevert(ChainlinkYieldOracle.InvalidPriceFeed.selector);
        oracle.addProtocol(AAVE_PROTOCOL, address(0));
    }
    
    function test_AddProtocol_RevertWhen_InvalidPriceFeed() public {
        // Create a mock that will fail validation
        MockV3Aggregator badFeed = new MockV3Aggregator(
            DECIMALS,
            -1, // negative yield
            1,
            1,
            block.timestamp,
            1
        );
        
        vm.prank(OWNER);
        vm.expectRevert(ChainlinkYieldOracle.InvalidPriceFeed.selector);
        oracle.addProtocol(AAVE_PROTOCOL, address(badFeed));
    }
    
    function test_AddProtocol_RevertWhen_ProtocolExists() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(OWNER);
        vm.expectRevert("Protocol already exists");
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
    }
    
    function test_RemoveProtocol() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(OWNER);
        oracle.removeProtocol(AAVE_PROTOCOL);
        
        assertFalse(oracle.isProtocolSupported(AAVE_PROTOCOL));
        
        bytes32[] memory protocols = oracle.getSupportedProtocols();
        assertEq(protocols.length, 0);
    }
    
    function test_RemoveProtocol_RevertWhen_NotOwner() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        oracle.removeProtocol(AAVE_PROTOCOL);
    }
    
    function test_RemoveProtocol_RevertWhen_ProtocolNotExists() public {
        vm.prank(OWNER);
        vm.expectRevert(ChainlinkYieldOracle.UnsupportedProtocol.selector);
        oracle.removeProtocol(AAVE_PROTOCOL);
    }
    
    function test_UpdateProtocolFeed() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(OWNER);
        oracle.updateProtocolFeed(AAVE_PROTOCOL, address(mockCompoundFeed));
        
        assertEq(address(oracle.protocolFeeds(AAVE_PROTOCOL)), address(mockCompoundFeed));
    }
    
    function test_UpdateProtocolFeed_RevertWhen_NotOwner() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        oracle.updateProtocolFeed(AAVE_PROTOCOL, address(mockCompoundFeed));
    }
    
    function test_UpdateProtocolFeed_RevertWhen_ProtocolNotExists() public {
        vm.prank(OWNER);
        vm.expectRevert(ChainlinkYieldOracle.UnsupportedProtocol.selector);
        oracle.updateProtocolFeed(AAVE_PROTOCOL, address(mockCompoundFeed));
    }
    
    function test_UpdateProtocolFeed_RevertWhen_ZeroPriceFeed() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(OWNER);
        vm.expectRevert(ChainlinkYieldOracle.InvalidPriceFeed.selector);
        oracle.updateProtocolFeed(AAVE_PROTOCOL, address(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                            YIELD QUERY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestYieldRate() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        (uint256 rate, uint256 timestamp) = oracle.getLatestYieldRate(AAVE_PROTOCOL);
        
        assertEq(rate, AAVE_YIELD);
        assertTrue(timestamp > 0);
    }
    
    function test_GetLatestYieldRate_RevertWhen_UnsupportedProtocol() public {
        vm.expectRevert(ChainlinkYieldOracle.UnsupportedProtocol.selector);
        oracle.getLatestYieldRate(AAVE_PROTOCOL);
    }
    
    function test_GetLatestYieldRate_RevertWhen_StaleRate() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        // Update with stale data
        mockAaveFeed.updateRoundData(
            2,
            int256(AAVE_YIELD),
            block.timestamp - MAX_RATE_AGE - 1,
            2
        );
        
        vm.expectRevert(ChainlinkYieldOracle.StaleRate.selector);
        oracle.getLatestYieldRate(AAVE_PROTOCOL);
    }
    
    function test_GetLatestYieldRate_RevertWhen_InvalidRate() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        // Update with invalid rate
        mockAaveFeed.updateRoundData(
            2,
            -1, // negative rate
            block.timestamp,
            2
        );
        
        vm.expectRevert(ChainlinkYieldOracle.InvalidRate.selector);
        oracle.getLatestYieldRate(AAVE_PROTOCOL);
    }
    
    function test_GetLatestYieldRate_RevertWhen_ZeroTimestamp() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        // Update with zero timestamp
        mockAaveFeed.updateRoundData(
            2,
            int256(AAVE_YIELD),
            0,
            2
        );
        
        vm.expectRevert(ChainlinkYieldOracle.StaleRate.selector);
        oracle.getLatestYieldRate(AAVE_PROTOCOL);
    }
    
    function test_GetLatestYieldRate_RevertWhen_RateTooLow() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        // Update with rate below minimum
        mockAaveFeed.updateRoundData(
            2,
            int256(oracle.MIN_RATE() - 1),
            block.timestamp,
            2
        );
        
        vm.expectRevert(ChainlinkYieldOracle.InvalidRate.selector);
        oracle.getLatestYieldRate(AAVE_PROTOCOL);
    }
    
    function test_GetLatestYieldRate_RevertWhen_RateTooHigh() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        // Update with rate above maximum
        mockAaveFeed.updateRoundData(
            2,
            int256(oracle.MAX_RATE() + 1),
            block.timestamp,
            2
        );
        
        vm.expectRevert(ChainlinkYieldOracle.InvalidRate.selector);
        oracle.getLatestYieldRate(AAVE_PROTOCOL);
    }
    
    function test_GetYieldRateAtRound() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        (uint256 rate, uint256 timestamp) = oracle.getYieldRateAtRound(AAVE_PROTOCOL, 1);
        
        assertEq(rate, AAVE_YIELD);
        assertTrue(timestamp > 0);
    }
    
    function test_GetYieldRateAtRound_RevertWhen_UnsupportedProtocol() public {
        vm.expectRevert(ChainlinkYieldOracle.UnsupportedProtocol.selector);
        oracle.getYieldRateAtRound(AAVE_PROTOCOL, 1);
    }
    
    function test_GetYieldRateAtRound_RevertWhen_InvalidRound() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.expectRevert(ChainlinkYieldOracle.InvalidRate.selector);
        oracle.getYieldRateAtRound(AAVE_PROTOCOL, 999);
    }
    
    function test_GetBatchYieldRates() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(OWNER);
        oracle.addProtocol(COMPOUND_PROTOCOL, address(mockCompoundFeed));
        
        bytes32[] memory protocolIds = new bytes32[](2);
        protocolIds[0] = AAVE_PROTOCOL;
        protocolIds[1] = COMPOUND_PROTOCOL;
        
        (uint256[] memory rates, uint256[] memory timestamps) = oracle.getBatchYieldRates(protocolIds);
        
        assertEq(rates.length, 2);
        assertEq(timestamps.length, 2);
        assertEq(rates[0], AAVE_YIELD);
        assertEq(rates[1], COMPOUND_YIELD);
        assertTrue(timestamps[0] > 0);
        assertTrue(timestamps[1] > 0);
    }
    
    function test_GetBatchYieldRates_WithUnsupportedProtocol() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        bytes32[] memory protocolIds = new bytes32[](2);
        protocolIds[0] = AAVE_PROTOCOL;
        protocolIds[1] = keccak256("UNSUPPORTED");
        
        (uint256[] memory rates, uint256[] memory timestamps) = oracle.getBatchYieldRates(protocolIds);
        
        assertEq(rates.length, 2);
        assertEq(timestamps.length, 2);
        assertEq(rates[0], AAVE_YIELD);
        assertEq(rates[1], 0); // Unsupported protocol
        assertTrue(timestamps[0] > 0);
        assertEq(timestamps[1], 0); // Unsupported protocol
    }
    
    function test_GetSupportedProtocols() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(OWNER);
        oracle.addProtocol(COMPOUND_PROTOCOL, address(mockCompoundFeed));
        
        bytes32[] memory protocols = oracle.getSupportedProtocols();
        assertEq(protocols.length, 2);
    }
    
    function test_IsProtocolSupported() public {
        assertFalse(oracle.isProtocolSupported(AAVE_PROTOCOL));
        
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        assertTrue(oracle.isProtocolSupported(AAVE_PROTOCOL));
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetMaxRateAge() public {
        uint256 newMaxAge = 30 minutes;
        
        vm.prank(OWNER);
        oracle.setMaxRateAge(newMaxAge);
        
        assertEq(oracle.maxRateAge(), newMaxAge);
    }
    
    function test_SetMaxRateAge_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        oracle.setMaxRateAge(30 minutes);
    }
    
    function test_SetMaxRateAge_RevertWhen_ZeroAge() public {
        vm.prank(OWNER);
        vm.expectRevert(ChainlinkYieldOracle.InvalidRate.selector);
        oracle.setMaxRateAge(0);
    }
    
    function test_SetMaxRateAge_RevertWhen_TooLarge() public {
        vm.prank(OWNER);
        vm.expectRevert(ChainlinkYieldOracle.InvalidRate.selector);
        oracle.setMaxRateAge(oracle.MAX_RATE_AGE() + 1);
    }
    
    function test_TransferOwnership() public {
        vm.prank(OWNER);
        oracle.transferOwnership(NEW_OWNER);
        
        assertEq(oracle.owner(), NEW_OWNER);
    }
    
    function test_TransferOwnership_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        oracle.transferOwnership(NEW_OWNER);
    }
    
    function test_TransferOwnership_RevertWhen_ZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert("Invalid owner");
        oracle.transferOwnership(address(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestYieldRate_MinimumValidRate() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        // Update with minimum valid rate
        mockAaveFeed.updateRoundData(
            2,
            int256(oracle.MIN_RATE()),
            block.timestamp,
            2
        );
        
        (uint256 rate, uint256 timestamp) = oracle.getLatestYieldRate(AAVE_PROTOCOL);
        
        assertEq(rate, oracle.MIN_RATE());
        assertTrue(timestamp > 0);
    }
    
    function test_GetLatestYieldRate_MaximumValidRate() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        // Update with maximum valid rate
        mockAaveFeed.updateRoundData(
            2,
            int256(oracle.MAX_RATE()),
            block.timestamp,
            2
        );
        
        (uint256 rate, uint256 timestamp) = oracle.getLatestYieldRate(AAVE_PROTOCOL);
        
        assertEq(rate, oracle.MAX_RATE());
        assertTrue(timestamp > 0);
    }
    
    function test_GetLatestYieldRate_ExactMaxAge() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        // Update with rate exactly at max age
        mockAaveFeed.updateRoundData(
            2,
            int256(AAVE_YIELD),
            block.timestamp - MAX_RATE_AGE,
            2
        );
        
        (uint256 rate, uint256 timestamp) = oracle.getLatestYieldRate(AAVE_PROTOCOL);
        
        assertEq(rate, AAVE_YIELD);
        assertTrue(timestamp > 0);
    }
    
    function test_RemoveProtocol_UpdatesArray() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(OWNER);
        oracle.addProtocol(COMPOUND_PROTOCOL, address(mockCompoundFeed));
        
        bytes32[] memory protocolsBefore = oracle.getSupportedProtocols();
        assertEq(protocolsBefore.length, 2);
        
        vm.prank(OWNER);
        oracle.removeProtocol(AAVE_PROTOCOL);
        
        bytes32[] memory protocolsAfter = oracle.getSupportedProtocols();
        assertEq(protocolsAfter.length, 1);
        assertEq(protocolsAfter[0], COMPOUND_PROTOCOL);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(oracle.MAX_RATE_AGE(), 1 hours);
        assertEq(oracle.MIN_RATE(), 0.01e8);
        assertEq(oracle.MAX_RATE(), 1000e8);
    }
    
    /*//////////////////////////////////////////////////////////////
                            EVENTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AddProtocol_Event() public {
        vm.expectEmit(true, true, true, true);
        emit ChainlinkYieldOracle.ProtocolAdded(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
    }
    
    function test_RemoveProtocol_Event() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.expectEmit(true, true, true, true);
        emit ChainlinkYieldOracle.ProtocolRemoved(AAVE_PROTOCOL);
        
        vm.prank(OWNER);
        oracle.removeProtocol(AAVE_PROTOCOL);
    }
    
    function test_UpdateProtocolFeed_Event() public {
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        vm.expectEmit(true, true, true, true);
        emit ChainlinkYieldOracle.PriceFeedUpdated(AAVE_PROTOCOL, address(mockAaveFeed), address(mockCompoundFeed));
        
        vm.prank(OWNER);
        oracle.updateProtocolFeed(AAVE_PROTOCOL, address(mockCompoundFeed));
    }
    
    function test_SetMaxRateAge_Event() public {
        uint256 newMaxAge = 30 minutes;
        
        vm.expectEmit(true, true, true, true);
        emit ChainlinkYieldOracle.MaxRateAgeUpdated(MAX_RATE_AGE, newMaxAge);
        
        vm.prank(OWNER);
        oracle.setMaxRateAge(newMaxAge);
    }
    
    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_GetLatestYieldRate_ValidRate(uint256 rate) public {
        // Bound rate to valid range
        rate = bound(rate, oracle.MIN_RATE(), oracle.MAX_RATE());
        
        vm.prank(OWNER);
        oracle.addProtocol(AAVE_PROTOCOL, address(mockAaveFeed));
        
        mockAaveFeed.updateRoundData(
            2,
            int256(rate),
            block.timestamp,
            2
        );
        
        (uint256 returnedRate, uint256 timestamp) = oracle.getLatestYieldRate(AAVE_PROTOCOL);
        
        assertEq(returnedRate, rate);
        assertTrue(timestamp > 0);
    }
    
    function testFuzz_SetMaxRateAge_ValidAge(uint256 age) public {
        age = bound(age, 1, oracle.MAX_RATE_AGE());
        
        vm.prank(OWNER);
        oracle.setMaxRateAge(age);
        
        assertEq(oracle.maxRateAge(), age);
    }
    
    function testFuzz_AddProtocol_ValidProtocol(bytes32 protocolId) public {
        // Skip zero protocol ID
        vm.assume(protocolId != bytes32(0));
        
        vm.prank(OWNER);
        oracle.addProtocol(protocolId, address(mockAaveFeed));
        
        assertTrue(oracle.isProtocolSupported(protocolId));
    }
}
