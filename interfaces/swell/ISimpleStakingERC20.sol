// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISimpleStakingERC20 {
    /// @notice Struct to hold the supported booleans
    /// @param deposit true if deposit is supported
    /// @param withdraw true if withdraw is supported
    struct Supported {
        bool deposit;
        bool withdraw;
    }

    /// @notice Error emitted when the amount is null
    error AMOUNT_NULL();

    /// @notice Error emitted when the address is null
    error ADDRESS_NULL();

    /// @notice Error emitted when the balance is insufficient
    error INSUFFICIENT_BALANCE();

    /// @notice Error emitted when the token is not allowed
    error TOKEN_NOT_ALLOWED(IERC20 token);

    /// @notice Event emitted when a token is added or removed
    /// @param token address of the token
    /// @param supported struct with deposit and withdraw booleans
    event SupportedToken(IERC20 indexed token, Supported supported);

    /// @notice Event emitted when a deposit is made
    /// @param token address of the token
    /// @param staker address of the staker
    /// @param amount amount of the deposit
    event Deposit(IERC20 indexed token, address indexed staker, uint256 amount);

    /// @notice Event emitted when a withdrawal is made
    /// @param token address of the token
    /// @param staker address of the staker
    /// @param amount amount of the withdrawal
    event Withdraw(IERC20 indexed token, address indexed staker, uint256 amount);

    /// @notice Method to deposit tokens
    /// @dev token are transferred from the sender, and the receiver is credited
    /// @param _token address of the token
    /// @param _amount amount to deposit
    /// @param _receiver address of the receiver
    function deposit(IERC20 _token, uint256 _amount, address _receiver) external;

    /// @notice Method to rescue tokens, only callable by the owner
    /// @dev difference between balance and internal balance is transferred to the owner
    /// @param _token address of the token
    function rescueERC20(IERC20 _token) external;

    /// @notice Method to add or remove a token
    /// @dev only callable by the owner
    /// @param _token address of the token
    /// @param _supported struct with deposit and withdraw booleans
    function supportToken(IERC20 _token, Supported calldata _supported) external;

    /// @notice Method to rescue tokens, callable by allowed operator or by public under some conditions
    /// @dev token are transferred to the receiver and sender is credited
    /// @param _token address of the token
    /// @param _amount amount to withdraw
    /// @param _receiver address of the receiver
    function withdraw(IERC20 _token, uint256 _amount, address _receiver) external;
}
