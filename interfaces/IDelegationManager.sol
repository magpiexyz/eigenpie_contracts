// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "./eigenlayer/IStrategy.sol";

/**
 * @title DelegationManager
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice  This is the contract for delegation in EigenLayer. The main functionalities of this contract are
 * - enabling anyone to register as an operator in EigenLayer
 * - allowing operators to specify parameters related to stakers who delegate to them
 * - enabling any staker to delegate its stake to the operator of its choice (a given staker can only delegate to a
 * single operator at a time)
 * - enabling a staker to undelegate its assets from the operator it is delegated to (performed as part of the
 * withdrawal process, initiated through the StrategyManager)
 */
interface IDelegationManager {
    struct QueuedWithdrawalParams {
        // Array of strategies that the QueuedWithdrawal contains
        IStrategy[] strategies;
        // Array containing the amount of shares in each Strategy in the `strategies` array
        uint256[] shares;
        // The address of the withdrawer
        address withdrawer;
    }

    function getDelegatableShares(address staker) external view returns (IStrategy[] memory, uint256[] memory);

    function queueWithdrawals(QueuedWithdrawalParams[] calldata queuedWithdrawalParams)
        external
        returns (bytes32[] memory);
}
