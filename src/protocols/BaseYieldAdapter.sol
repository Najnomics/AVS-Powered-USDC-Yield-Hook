// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BaseYieldAdapter
 * @author AVS Yield Labs
 * @notice Abstract base contract for yield protocol adapters
 * @dev All yield protocol integrations should inherit from this contract
 */
abstract contract BaseYieldAdapter {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC token address
    address public constant USDC = 0xA0B86a33E6441a8ec76D8b5d8E0e0F24DA3e0e6F;
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Protocol identifier
    bytes32 public immutable protocolId;
    
    /// @notice Protocol name
    string public protocolName;
    
    /// @notice Whether the adapter is active
    bool public isActive;
    
    /// @notice Minimum deposit amount
    uint256 public minDeposit;
    
    /// @notice Maximum TVL limit
    uint256 public maxTvl;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);
    event YieldClaimed(address indexed user, uint256 amount);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(bytes32 _protocolId, string memory _protocolName) {
        protocolId = _protocolId;
        protocolName = _protocolName;
        isActive = true;
    }
    
    /*//////////////////////////////////////////////////////////////
                        ABSTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deposit USDC into the yield protocol
     * @param amount Amount of USDC to deposit
     * @return shares Amount of shares/tokens received
     */
    function deposit(uint256 amount) external virtual returns (uint256 shares);
    
    /**
     * @notice Withdraw USDC from the yield protocol
     * @param shares Amount of shares/tokens to withdraw
     * @return amount Amount of USDC received
     */
    function withdraw(uint256 shares) external virtual returns (uint256 amount);
    
    /**
     * @notice Get current yield rate (APY)
     * @return yieldRate Current yield rate in basis points
     */
    function getCurrentYield() external view virtual returns (uint256 yieldRate);
    
    /**
     * @notice Get user's balance in the protocol
     * @param user User address
     * @return shares User's share balance
     * @return value Equivalent USDC value
     */
    function getUserBalance(address user) external view virtual returns (uint256 shares, uint256 value);
    
    /**
     * @notice Get protocol's total value locked
     * @return tvl Total value locked in USDC
     */
    function getTotalValueLocked() external view virtual returns (uint256 tvl);
    
    /**
     * @notice Get protocol utilization rate
     * @return utilization Utilization rate in basis points
     */
    function getUtilization() external view virtual returns (uint256 utilization);
    
    /**
     * @notice Get protocol risk score
     * @return riskScore Risk score (0-10000, lower is safer)
     */
    function getRiskScore() external view virtual returns (uint256 riskScore);
    
    /**
     * @notice Check if protocol can accept more deposits
     * @param amount Amount to potentially deposit
     * @return canDeposit Whether deposit is possible
     * @return maxDepositAmount Maximum amount that can be deposited
     */
    function canDeposit(uint256 amount) external view virtual returns (bool canDeposit, uint256 maxDepositAmount);
    
    /**
     * @notice Get withdrawal availability
     * @param shares Amount of shares to withdraw
     * @return canWithdraw Whether withdrawal is possible
     * @return availableShares Maximum shares that can be withdrawn
     */
    function canWithdraw(uint256 shares) external view virtual returns (bool canWithdraw, uint256 availableShares);
    
    /*//////////////////////////////////////////////////////////////
                        COMMON FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get adapter information
     * @return id Protocol identifier
     * @return name Protocol name
     * @return active Whether adapter is active
     * @return minDep Minimum deposit amount
     * @return maxTvlLimit Maximum TVL limit
     */
    function getAdapterInfo() external view returns (
        bytes32 id,
        string memory name,
        bool active,
        uint256 minDep,
        uint256 maxTvlLimit
    ) {
        return (protocolId, protocolName, isActive, minDeposit, maxTvl);
    }
    
    /**
     * @notice Calculate shares for a given USDC amount
     * @param amount USDC amount
     * @return shares Equivalent shares
     */
    function calculateShares(uint256 amount) external view virtual returns (uint256 shares) {
        // Default 1:1 ratio, override in specific adapters
        return amount;
    }
    
    /**
     * @notice Calculate USDC amount for given shares
     * @param shares Share amount
     * @return amount Equivalent USDC amount
     */
    function calculateAmount(uint256 shares) external view virtual returns (uint256 amount) {
        // Default 1:1 ratio, override in specific adapters
        return shares;
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Validate deposit parameters
     * @param amount Deposit amount
     */
    function _validateDeposit(uint256 amount) internal view {
        require(isActive, "Adapter not active");
        require(amount >= minDeposit, "Amount below minimum");
        require(amount > 0, "Invalid amount");
        
        uint256 currentTvl = this.getTotalValueLocked();
        require(currentTvl + amount <= maxTvl, "TVL limit exceeded");
    }
    
    /**
     * @notice Validate withdrawal parameters
     * @param shares Share amount
     */
    function _validateWithdraw(uint256 shares) internal view {
        require(isActive, "Adapter not active");
        require(shares > 0, "Invalid shares");
    }
    
    /**
     * @notice Transfer USDC from user
     * @param from User address
     * @param amount Amount to transfer
     */
    function _transferUSDCFrom(address from, uint256 amount) internal {
        require(IERC20(USDC).transferFrom(from, address(this), amount), "USDC transfer failed");
    }
    
    /**
     * @notice Transfer USDC to user
     * @param to User address
     * @param amount Amount to transfer
     */
    function _transferUSDC(address to, uint256 amount) internal {
        require(IERC20(USDC).transfer(to, amount), "USDC transfer failed");
    }
}