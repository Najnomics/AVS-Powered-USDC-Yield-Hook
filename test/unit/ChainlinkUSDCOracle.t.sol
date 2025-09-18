// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {ChainlinkUSDCOracle} from "../../src/oracles/ChainlinkUSDCOracle.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

/**
 * @title ChainlinkUSDCOracleUnitTest
 * @notice Comprehensive unit tests for ChainlinkUSDCOracle
 * @dev Tests all functions, edge cases, and error conditions
 */
contract ChainlinkUSDCOracleUnitTest is Test {
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    ChainlinkUSDCOracle public oracle;
    MockV3Aggregator public mockPriceFeed;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant OWNER = address(0x1);
    address constant NEW_OWNER = address(0x2);
    
    uint256 constant INITIAL_PRICE = 1e8; // $1.00 (8 decimals)
    uint256 constant UPDATED_PRICE = 105e6; // $1.05 (8 decimals)
    uint8 constant DECIMALS = 8;
    uint256 constant MAX_PRICE_AGE = 24 hours;
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Deploy mock price feed
        mockPriceFeed = new MockV3Aggregator(
            DECIMALS,
            int256(INITIAL_PRICE),
            1, // roundId
            1, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );
        
        // Deploy oracle
        oracle = new ChainlinkUSDCOracle(
            address(mockPriceFeed),
            MAX_PRICE_AGE
        );
        
        // Transfer ownership to test contract
        oracle.transferOwnership(OWNER);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(address(oracle.priceFeed()), address(mockPriceFeed));
        assertEq(oracle.maxPriceAge(), MAX_PRICE_AGE);
        assertEq(oracle.owner(), OWNER);
    }
    
    function test_Constructor_RevertWhen_ZeroPriceFeed() public {
        vm.expectRevert(ChainlinkUSDCOracle.InvalidPriceFeed.selector);
        new ChainlinkUSDCOracle(
            address(0),
            MAX_PRICE_AGE
        );
    }
    
    function test_Constructor_RevertWhen_InvalidPriceFeed() public {
        // Create a mock that will fail validation
        MockV3Aggregator badFeed = new MockV3Aggregator(
            DECIMALS,
            -1, // negative price
            1,
            1,
            block.timestamp,
            1
        );
        
        vm.expectRevert(ChainlinkUSDCOracle.InvalidPriceFeed.selector);
        new ChainlinkUSDCOracle(
            address(badFeed),
            MAX_PRICE_AGE
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            PRICE QUERY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestPrice() public {
        (uint256 price, uint256 timestamp) = oracle.getLatestPrice();
        
        assertEq(price, INITIAL_PRICE);
        assertTrue(timestamp > 0);
    }
    
    function test_GetLatestPrice_RevertWhen_StalePrice() public {
        // Update price feed with old timestamp
        mockPriceFeed.updateRoundData(
            2, // roundId
            int256(UPDATED_PRICE),
            block.timestamp - MAX_PRICE_AGE - 1, // too old
            2 // answeredInRound
        );
        
        vm.expectRevert(ChainlinkUSDCOracle.StalePrice.selector);
        oracle.getLatestPrice();
    }
    
    function test_GetLatestPrice_RevertWhen_InvalidPrice() public {
        // Update price feed with invalid price
        mockPriceFeed.updateRoundData(
            2,
            -1, // negative price
            block.timestamp,
            2
        );
        
        vm.expectRevert(ChainlinkUSDCOracle.InvalidPrice.selector);
        oracle.getLatestPrice();
    }
    
    function test_GetLatestPrice_RevertWhen_ZeroTimestamp() public {
        // Update price feed with zero timestamp
        mockPriceFeed.updateRoundData(
            2,
            int256(UPDATED_PRICE),
            0, // zero timestamp
            2
        );
        
        vm.expectRevert(ChainlinkUSDCOracle.StalePrice.selector);
        oracle.getLatestPrice();
    }
    
    function test_GetLatestPrice_RevertWhen_PriceTooLow() public {
        // Update price feed with price below minimum
        mockPriceFeed.updateRoundData(
            2,
            int256(oracle.MIN_PRICE() - 1),
            block.timestamp,
            2
        );
        
        vm.expectRevert(ChainlinkUSDCOracle.InvalidPrice.selector);
        oracle.getLatestPrice();
    }
    
    function test_GetLatestPrice_RevertWhen_PriceTooHigh() public {
        // Update price feed with price above maximum
        mockPriceFeed.updateRoundData(
            2,
            int256(oracle.MAX_PRICE() + 1),
            block.timestamp,
            2
        );
        
        vm.expectRevert(ChainlinkUSDCOracle.InvalidPrice.selector);
        oracle.getLatestPrice();
    }
    
    function test_GetPriceAtRound() public {
        (uint256 price, uint256 timestamp) = oracle.getPriceAtRound(1);
        
        assertEq(price, INITIAL_PRICE);
        assertTrue(timestamp > 0);
    }
    
    function test_GetPriceAtRound_RevertWhen_InvalidRound() public {
        vm.expectRevert(ChainlinkUSDCOracle.InvalidPrice.selector);
        oracle.getPriceAtRound(999); // non-existent round
    }
    
    function test_GetLatestRoundId() public {
        uint80 roundId = oracle.getLatestRoundId();
        assertEq(roundId, 1);
    }
    
    function test_GetRoundData() public {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.getRoundData(1);
        
        assertEq(roundId, 1);
        assertEq(answer, int256(INITIAL_PRICE));
        assertTrue(startedAt > 0);
        assertTrue(updatedAt > 0);
        assertEq(answeredInRound, 1);
    }
    
    function test_Decimals() public {
        assertEq(oracle.decimals(), DECIMALS);
    }
    
    function test_Description() public {
        string memory desc = oracle.description();
        assertTrue(bytes(desc).length > 0);
    }
    
    function test_Version() public {
        uint256 version = oracle.version();
        assertTrue(version > 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetMaxPriceAge() public {
        uint256 newMaxAge = 12 hours;
        
        vm.prank(OWNER);
        oracle.setMaxPriceAge(newMaxAge);
        
        assertEq(oracle.maxPriceAge(), newMaxAge);
    }
    
    function test_SetMaxPriceAge_RevertWhen_NotOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert("Unauthorized");
        oracle.setMaxPriceAge(12 hours);
    }
    
    function test_SetMaxPriceAge_RevertWhen_ZeroAge() public {
        vm.prank(OWNER);
        vm.expectRevert(ChainlinkUSDCOracle.InvalidPrice.selector);
        oracle.setMaxPriceAge(0);
    }
    
    function test_SetMaxPriceAge_RevertWhen_TooLarge() public {
        vm.prank(OWNER);
        vm.expectRevert(ChainlinkUSDCOracle.InvalidPrice.selector);
        oracle.setMaxPriceAge(oracle.MAX_PRICE_AGE() + 1);
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
    
    function test_GetLatestPrice_AfterUpdate() public {
        // Update price feed
        mockPriceFeed.updateRoundData(
            2,
            int256(UPDATED_PRICE),
            block.timestamp,
            2
        );
        
        (uint256 price, uint256 timestamp) = oracle.getLatestPrice();
        
        assertEq(price, UPDATED_PRICE);
        assertTrue(timestamp > 0);
    }
    
    function test_GetLatestPrice_MinimumValidPrice() public {
        // Update with minimum valid price
        mockPriceFeed.updateRoundData(
            2,
            int256(oracle.MIN_PRICE()),
            block.timestamp,
            2
        );
        
        (uint256 price, uint256 timestamp) = oracle.getLatestPrice();
        
        assertEq(price, oracle.MIN_PRICE());
        assertTrue(timestamp > 0);
    }
    
    function test_GetLatestPrice_MaximumValidPrice() public {
        // Update with maximum valid price
        mockPriceFeed.updateRoundData(
            2,
            int256(oracle.MAX_PRICE()),
            block.timestamp,
            2
        );
        
        (uint256 price, uint256 timestamp) = oracle.getLatestPrice();
        
        assertEq(price, oracle.MAX_PRICE());
        assertTrue(timestamp > 0);
    }
    
    function test_GetLatestPrice_ExactMaxAge() public {
        // Update with price exactly at max age
        mockPriceFeed.updateRoundData(
            2,
            int256(UPDATED_PRICE),
            block.timestamp - MAX_PRICE_AGE,
            2
        );
        
        (uint256 price, uint256 timestamp) = oracle.getLatestPrice();
        
        assertEq(price, UPDATED_PRICE);
        assertTrue(timestamp > 0);
    }
    
    function test_GetPriceAtRound_StalePrice() public {
        // Update round 2 with stale data
        mockPriceFeed.updateRoundData(
            2,
            int256(UPDATED_PRICE),
            block.timestamp - MAX_PRICE_AGE - 1,
            2
        );
        
        vm.expectRevert(ChainlinkUSDCOracle.StalePrice.selector);
        oracle.getPriceAtRound(2);
    }
    
    function test_GetPriceAtRound_InvalidPrice() public {
        // Update round 2 with invalid price
        mockPriceFeed.updateRoundData(
            2,
            -1,
            block.timestamp,
            2
        );
        
        vm.expectRevert(ChainlinkUSDCOracle.InvalidPrice.selector);
        oracle.getPriceAtRound(2);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(oracle.MAX_PRICE_AGE(), 24 hours);
        assertEq(oracle.MIN_PRICE(), 0.01e8);
        assertEq(oracle.MAX_PRICE(), 1000e8);
    }
    
    /*//////////////////////////////////////////////////////////////
                            EVENTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetMaxPriceAge_Event() public {
        uint256 newMaxAge = 12 hours;
        
        vm.expectEmit(true, true, true, true);
        emit ChainlinkUSDCOracle.MaxPriceAgeUpdated(MAX_PRICE_AGE, newMaxAge);
        
        vm.prank(OWNER);
        oracle.setMaxPriceAge(newMaxAge);
    }
    
    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_GetLatestPrice_ValidPrice(uint256 price) public {
        // Bound price to valid range
        price = bound(price, oracle.MIN_PRICE(), oracle.MAX_PRICE());
        
        mockPriceFeed.updateRoundData(
            2,
            int256(price),
            block.timestamp,
            2
        );
        
        (uint256 returnedPrice, uint256 timestamp) = oracle.getLatestPrice();
        
        assertEq(returnedPrice, price);
        assertTrue(timestamp > 0);
    }
    
    function testFuzz_SetMaxPriceAge_ValidAge(uint256 age) public {
        age = bound(age, 1, oracle.MAX_PRICE_AGE());
        
        vm.prank(OWNER);
        oracle.setMaxPriceAge(age);
        
        assertEq(oracle.maxPriceAge(), age);
    }
    
    function testFuzz_GetPriceAtRound_ValidRound(uint80 roundId) public {
        // Use existing round
        roundId = 1;
        
        (uint256 price, uint256 timestamp) = oracle.getPriceAtRound(roundId);
        
        assertEq(price, INITIAL_PRICE);
        assertTrue(timestamp > 0);
    }
}
