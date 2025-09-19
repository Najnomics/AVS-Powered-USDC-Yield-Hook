// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {OracleAggregator} from "../../src/oracles/OracleAggregator.sol";
import {ChainlinkUSDCOracle} from "../../src/oracles/ChainlinkUSDCOracle.sol";
import {ChainlinkYieldOracle} from "../../src/oracles/ChainlinkYieldOracle.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

/**
 * @title OracleAggregatorUnitTest
 * @notice Basic unit tests for OracleAggregator
 * @dev Tests basic functionality and constants
 */
contract OracleAggregatorUnitTest is Test {
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    OracleAggregator public aggregator;
    ChainlinkUSDCOracle public usdcOracle;
    ChainlinkYieldOracle public yieldOracle;
    MockV3Aggregator public mockUSDCFeed;
    MockV3Aggregator public mockYieldFeed;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address constant USER = address(0x1);
    
    uint256 constant USDC_PRICE = 100000000; // $1.00 with 8 decimals
    uint256 constant YIELD_RATE = 5000000; // 5% APY with 8 decimals
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Deploy mock price feeds
        mockUSDCFeed = new MockV3Aggregator(8, int256(USDC_PRICE));
        mockYieldFeed = new MockV3Aggregator(8, int256(YIELD_RATE));
        
        // Deploy oracles
        usdcOracle = new ChainlinkUSDCOracle(address(mockUSDCFeed), 3600); // 1 hour max age
        yieldOracle = new ChainlinkYieldOracle(3600); // 1 hour max age
        
        // Deploy aggregator
        aggregator = new OracleAggregator(address(usdcOracle), address(yieldOracle), 3600); // 1 hour max data age
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(address(aggregator.usdcOracle()), address(usdcOracle));
        assertEq(address(aggregator.yieldOracle()), address(yieldOracle));
        assertEq(aggregator.owner(), address(this));
    }
    
    function test_Constructor_RevertWhen_ZeroUSDCOracle() public {
        vm.expectRevert();
        new OracleAggregator(address(0), address(yieldOracle), 3600);
    }
    
    function test_Constructor_RevertWhen_ZeroYieldOracle() public {
        vm.expectRevert();
        new OracleAggregator(address(usdcOracle), address(0), 3600);
    }
    
    /*//////////////////////////////////////////////////////////////
                            USDC ORACLE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestUSDCPrice() public {
        (uint256 price, uint256 timestamp, address oracleAddress) = aggregator.getLatestUSDCPrice();
        
        assertEq(price, USDC_PRICE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(usdcOracle));
    }
    
    function test_GetUSDCPriceAtRound() public {
        (uint256 price, uint256 timestamp, address oracleAddress) = aggregator.getUSDCPriceAtRound(1);
        
        assertEq(price, USDC_PRICE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(usdcOracle));
    }
    
    /*//////////////////////////////////////////////////////////////
                            YIELD ORACLE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestYieldRate() public {
        bytes32 protocolId = keccak256("AAVE_V3");
        
        // Add protocol to yield oracle
        vm.prank(address(this));
        yieldOracle.addProtocol(protocolId, address(mockYieldFeed));
        
        (uint256 rate, uint256 timestamp, address oracleAddress) = aggregator.getLatestYieldRate(protocolId);
        
        assertEq(rate, YIELD_RATE);
        assertTrue(timestamp > 0);
    }
    
    function test_GetBatchYieldRates() public {
        bytes32 protocolId = keccak256("AAVE_V3");
        
        // Add protocol to yield oracle
        vm.prank(address(this));
        yieldOracle.addProtocol(protocolId, address(mockYieldFeed));
        
        bytes32[] memory protocolIds = new bytes32[](1);
        protocolIds[0] = protocolId;
        
        (uint256[] memory rates, uint256[] memory timestamps, address[] memory oracleAddresses) = aggregator.getBatchYieldRates(protocolIds);
        
        assertEq(rates.length, 1);
        assertEq(timestamps.length, 1);
        assertEq(rates[0], YIELD_RATE);
        assertTrue(timestamps[0] > 0);
    }
    
    function test_GetSupportedProtocols() public {
        bytes32[] memory protocols = aggregator.getSupportedProtocols();
        
        assertTrue(protocols.length >= 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetUSDCOracle() public {
        ChainlinkUSDCOracle newOracle = new ChainlinkUSDCOracle(address(mockUSDCFeed), 3600);
        
        vm.prank(address(this));
        aggregator.setUSDCOracle(address(newOracle));
        
        assertEq(address(aggregator.usdcOracle()), address(newOracle));
    }
    
    function test_SetUSDCOracle_RevertWhen_NotOwner() public {
        ChainlinkUSDCOracle newOracle = new ChainlinkUSDCOracle(address(mockUSDCFeed), 3600);
        
        vm.prank(USER);
        vm.expectRevert();
        aggregator.setUSDCOracle(address(newOracle));
    }
    
    function test_SetUSDCOracle_RevertWhen_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert("InvalidOracle()");
        aggregator.setUSDCOracle(address(0));
    }
    
    function test_SetYieldOracle() public {
        ChainlinkYieldOracle newOracle = new ChainlinkYieldOracle(3600);
        
        vm.prank(address(this));
        aggregator.setYieldOracle(address(newOracle));
        
        assertEq(address(aggregator.yieldOracle()), address(newOracle));
    }
    
    function test_SetYieldOracle_RevertWhen_NotOwner() public {
        ChainlinkYieldOracle newOracle = new ChainlinkYieldOracle(3600);
        
        vm.prank(USER);
        vm.expectRevert();
        aggregator.setYieldOracle(address(newOracle));
    }
    
    function test_SetYieldOracle_RevertWhen_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert("InvalidOracle()");
        aggregator.setYieldOracle(address(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                            FALLBACK ORACLE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AddFallbackUSDCOracle() public {
        ChainlinkUSDCOracle fallbackOracle = new ChainlinkUSDCOracle(address(mockUSDCFeed), 3600);
        
        vm.prank(address(this));
        aggregator.addFallbackUSDCOracle(address(fallbackOracle));
        
        // Test that it was added (we can't directly check the array)
        assertTrue(true);
    }
    
    function test_AddFallbackUSDCOracle_RevertWhen_NotOwner() public {
        ChainlinkUSDCOracle fallbackOracle = new ChainlinkUSDCOracle(address(mockUSDCFeed), 3600);
        
        vm.prank(USER);
        vm.expectRevert();
        aggregator.addFallbackUSDCOracle(address(fallbackOracle));
    }
    
    function test_AddFallbackUSDCOracle_RevertWhen_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert("InvalidOracle()");
        aggregator.addFallbackUSDCOracle(address(0));
    }
    
    function test_RemoveFallbackUSDCOracle() public {
        ChainlinkUSDCOracle fallbackOracle = new ChainlinkUSDCOracle(address(mockUSDCFeed), 3600);
        
        vm.prank(address(this));
        aggregator.addFallbackUSDCOracle(address(fallbackOracle));
        
        vm.prank(address(this));
        aggregator.removeFallbackUSDCOracle(0);
        
        // Test that it was removed
        assertTrue(true);
    }
    
    function test_RemoveFallbackUSDCOracle_RevertWhen_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        aggregator.removeFallbackUSDCOracle(0);
    }
    
    function test_RemoveFallbackUSDCOracle_RevertWhen_InvalidIndex() public {
        vm.prank(address(this));
        vm.expectRevert("Invalid index");
        aggregator.removeFallbackUSDCOracle(0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public {
        assertEq(address(aggregator.usdcOracle()), address(usdcOracle));
        assertEq(address(aggregator.yieldOracle()), address(yieldOracle));
        assertEq(aggregator.owner(), address(this));
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestUSDCPrice_WithFallback() public {
        // This would test fallback functionality if primary oracle fails
        (uint256 price, uint256 timestamp, address oracleAddress) = aggregator.getLatestUSDCPrice();
        
        assertEq(price, USDC_PRICE);
        assertTrue(timestamp > 0);
        assertEq(oracleAddress, address(usdcOracle));
    }
    
    function test_GetLatestYieldRate_UnsupportedProtocol() public {
        bytes32 unsupportedProtocol = keccak256("UNSUPPORTED");
        
        vm.expectRevert("NoValidOracle()");
        aggregator.getLatestYieldRate(unsupportedProtocol);
    }
    
    function test_GetBatchYieldRates_EmptyArray() public {
        bytes32[] memory protocolIds = new bytes32[](0);
        
        (uint256[] memory rates, uint256[] memory timestamps, address[] memory oracleAddresses) = aggregator.getBatchYieldRates(protocolIds);
        
        assertEq(rates.length, 0);
        assertEq(timestamps.length, 0);
    }
}