// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { IDelegationManager } from "./eigenlayer/IDelegationManager.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IEigenpieWithdrawManager {
    struct UserWithdrawalSchedule {
        uint256 receiptMLRTAmt;
        uint256 queuedWithdrawLSTAmt;
        uint256 claimedAmt;
        uint256 endTime;
    }

    struct WithdrawalSum {
        uint256 assetTotalToWithdrawAmt;
        uint256 assetTotalWithdrawQueued;
        uint256 mLRTTotalToBurn;
        bool mLRTburnt;
    }

    //errors
    error InvalidAmount();
    error LengthMismatch();
    error EpochNotYetReached();
    error NotWithdrawAllQueuedRequest();
    error NativeWithdrawNotSupported();

    //events
    event UserQueuingForWithdrawal(
        address indexed user,
        address indexed asset,
        uint256 mLRTAmount,
        uint256 LSTAmt,
        uint256 currentEpoch,
        uint256 endTime
    );
    event AssetWithdrawn(address indexed user, address indexed asset, uint256 LSTAmt);
    event EpochUpdated(uint256 newEpochTime);
    event VestingWithdrawalCleanUpThresholdUpdated(uint256 newThreshold);
}
