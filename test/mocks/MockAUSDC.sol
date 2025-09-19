// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockAUSDC
 * @notice Mock Aave USDC aToken for testing
 * @dev Simulates Aave V3 aUSDC token behavior
 */
contract MockAUSDC is ERC20 {
    constructor() ERC20("Aave USDC", "aUSDC") {
        _mint(msg.sender, 1000000e6); // Mint 1M aUSDC to deployer
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
