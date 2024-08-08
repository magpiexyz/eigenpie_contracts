// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "./utils/UtilLib.sol";
import { EigenpieConstants } from "./utils/EigenpieConstants.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { EigenpieConfigRoleChecker, IEigenpieConfig } from "./utils/EigenpieConfigRoleChecker.sol";
import { IMintableERC20 } from "./interfaces/IMintableERC20.sol";
import { INodeDelegator } from "./interfaces/INodeDelegator.sol";
import { IEigenpieStaking } from "./interfaces/IEigenpieStaking.sol";
import { IMLRT } from "./interfaces/IMLRT.sol";
import { IEigenpiePreDepositHelper } from "./interfaces/IEigenpiePreDepositHelper.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IEigenpieWithdrawManager } from "./interfaces/IEigenpieWithdrawManager.sol";

/// @title EigenpieWithdrawManager - Withdraw Pool Contract for LSTs
/// @notice Handles LST asset deposits
contract EigenpieWithdrawManager is
    IEigenpieWithdrawManager,
    EigenpieConfigRoleChecker,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    uint256 public lstWithdrawalDelay; // a buffer time period making sure user able to withdraw the LST unstake by
        // Eigenpie
    uint256 public startTimestamp; // the start timestamp counting epoch
    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public withdrawalscheduleCleanUp; // the threshold to clean up withdra queue length

    mapping(bytes32 => UserWithdrawalSchedule[]) public withdrawalSchedules; //bytes32 = user + asset
    mapping(bytes32 => WithdrawalSum) public withdrawalSums; // aggregated withdrawal information // bytes32 = asset +
        // epochTime

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfigAddr eigenpieConfig address
    function initialize(
        address eigenpieConfigAddr,
        uint256 _lstWithdrawalDelay,
        uint256 _startTimestamp
    )
        external
        initializer
    {
        UtilLib.checkNonZeroAddress(eigenpieConfigAddr);

        __Pausable_init();
        __ReentrancyGuard_init();

        eigenpieConfig = IEigenpieConfig(eigenpieConfigAddr);
        lstWithdrawalDelay = _lstWithdrawalDelay;
        startTimestamp = _startTimestamp;
        withdrawalscheduleCleanUp = 5;

        emit UpdatedEigenpieConfig(eigenpieConfigAddr);
    }

    /*//////////////////////////////////////////////////////////////
                            view functions
    //////////////////////////////////////////////////////////////*/

    // to get timestamp user able to unstake LST from Eigenpie if they queue withdraw now
    function nextUserWithdrawalTime() external view returns (uint256) {
        return startTimestamp + (currentEpoch() + 1) * EPOCH_DURATION + lstWithdrawalDelay;
    }

    // to get current epoch number
    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - startTimestamp) / EPOCH_DURATION + 1;
    }

    function getUserQueuedWithdraw(
        address _user,
        address[] memory _assets
    )
        external
        view
        returns (uint256[] memory queuedAmounts, uint256[] memory claimableAmounts, uint256[] memory claimedAmounts)
    {
        return _calculateAmounts(_user, _assets);
    }

    function userToAssetKey(address _user, address _asset) public pure returns (bytes32) {
        return _getKey(_user, _asset, 0, true);
    }

    function assetEpochKey(address _asset, uint256 _epochTime) public pure returns (bytes32) {
        return _getKey(address(0), _asset, _epochTime, false);
    }

    function getUserWithdrawalSchedules(
        address user,
        address[] memory assets
    )
        external
        view
        returns (uint256[][] memory queuedLstAmounts, uint256[][] memory endTimes)
    {
        queuedLstAmounts = new uint256[][](assets.length);
        endTimes = new uint256[][](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            bytes32 key = userToAssetKey(user, assets[i]);
            UserWithdrawalSchedule[] memory schedules = withdrawalSchedules[key];

            // Initialize arrays to store schedules for the current asset
            uint256[] memory assetQueuedAmounts = new uint256[](schedules.length);
            uint256[] memory assetEndTimes = new uint256[](schedules.length);

            // Iterate through all schedules for the current asset
            for (uint256 j = 0; j < schedules.length; j++) {
                UserWithdrawalSchedule memory schedule = schedules[j];
                assetQueuedAmounts[j] = schedule.queuedWithdrawLSTAmt;
                assetEndTimes[j] = schedule.endTime;
            }

            // Assign arrays to the corresponding row in queuedAmounts and endTimes
            queuedLstAmounts[i] = assetQueuedAmounts;
            endTimes[i] = assetEndTimes;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            Write functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allows a user to queue for withdrawal of a specific asset.
     * @param asset The address of the asset to withdraw.
     * @param mLRTamount The amount of the mLRT Token respective of LST token to withdraw.
     */
    function userQueuingForWithdraw(
        address asset,
        uint256 mLRTamount
    )
        external
        whenNotPaused
        nonReentrant
        onlySupportedAsset(asset)
    {
        if (asset == EigenpieConstants.PLATFORM_TOKEN_ADDRESS) revert NativeWithdrawNotSupported();

        address receipt = eigenpieConfig.mLRTReceiptByAsset(asset);
        uint256 userReceiptBal = IERC20(receipt).balanceOf(msg.sender);
        if (mLRTamount > userReceiptBal) revert InvalidAmount();

        uint256 epochCurr = this.currentEpoch();

        bytes32 userToAsset = userToAssetKey(msg.sender, asset);
        bytes32 assetToEpoch = assetEpochKey(asset, epochCurr);

        uint256 rate = IMLRT(receipt).exchangeRateToLST();
        uint256 withdrawLSTAmt = (rate * mLRTamount) / 1 ether;
        uint256 userWithdrawableTime = this.nextUserWithdrawalTime();
        withdrawalSchedules[userToAsset].push(
            UserWithdrawalSchedule(mLRTamount, withdrawLSTAmt, 0, userWithdrawableTime)
        );

        WithdrawalSum storage withdrawalSum = withdrawalSums[assetToEpoch];
        withdrawalSum.assetTotalToWithdrawAmt += withdrawLSTAmt;
        withdrawalSum.mLRTTotalToBurn += mLRTamount;

        IERC20(receipt).safeTransferFrom(msg.sender, address(this), mLRTamount);

        emit UserQueuingForWithdrawal(msg.sender, asset, mLRTamount, withdrawLSTAmt, epochCurr, userWithdrawableTime);
    }

    function userWithdrawAsset(address[] memory assets) external nonReentrant {
        uint256[] memory claimedWithdrawalSchedules = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length;) {
            bytes32 userToAsset = userToAssetKey(msg.sender, assets[i]);
            UserWithdrawalSchedule[] storage schedules = withdrawalSchedules[userToAsset];

            uint256 totalClaimedAmount;
            uint256 claimedWithdrawalSchedulesPerAsset;

            for (uint256 j = 0; j < schedules.length;) {
                UserWithdrawalSchedule storage schedule = schedules[j];

                // if claimmable
                if (block.timestamp >= schedule.endTime && schedule.claimedAmt == 0) {
                    claimedWithdrawalSchedulesPerAsset++;

                    schedule.claimedAmt = schedule.queuedWithdrawLSTAmt;
                    totalClaimedAmount += schedule.queuedWithdrawLSTAmt;
                } else if (block.timestamp >= schedule.endTime && schedule.claimedAmt == schedule.queuedWithdrawLSTAmt)
                {
                    claimedWithdrawalSchedulesPerAsset++;
                }

                unchecked {
                    ++j;
                }
            }

            claimedWithdrawalSchedules[i] = claimedWithdrawalSchedulesPerAsset;

            if (totalClaimedAmount > 0) {
                IERC20(assets[i]).safeTransfer(msg.sender, totalClaimedAmount);
                emit AssetWithdrawn(msg.sender, assets[i], totalClaimedAmount);
            }

            unchecked {
                ++i;
            }
        }

        _cleanUpWithdrawalSchedules(assets, claimedWithdrawalSchedules);
    }

    /*//////////////////////////////////////////////////////////////
                            Admin functions
    //////////////////////////////////////////////////////////////*/

    // admin to queue Withdraw for aggregated user withdraw reqeust
    // Huge Assumption!! Admin should always fully queue withdraw all aggregated assets in that epoch
    function queuingWithdraw(
        address[] memory nodeDelegators,
        address[][] memory nodeToAssets,
        uint256[][] memory nodeToAmounts,
        uint256 epochNumber
    )
        external
        onlyAllowedBot
    {
        if (nodeDelegators.length != nodeToAssets.length || nodeDelegators.length != nodeToAmounts.length) {
            revert LengthMismatch();
        }

        for (uint256 i = 0; i < nodeDelegators.length;) {
            if (nodeToAssets[i].length != nodeToAmounts[i].length) {
                revert LengthMismatch();
            }

            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < nodeDelegators.length;) {
            uint256 assetsLength = nodeToAssets[i].length;

            for (uint256 j = 0; j < assetsLength;) {
                bytes32 assetToEpochKey = keccak256(abi.encodePacked(nodeToAssets[i][j], epochNumber));
                WithdrawalSum storage withdrawalSum = withdrawalSums[assetToEpochKey];
                withdrawalSum.assetTotalWithdrawQueued += nodeToAmounts[i][j];
                withdrawalSum.mLRTburnt = true;

                unchecked {
                    ++j;
                }
            }
            INodeDelegator(nodeDelegators[i]).queueWithdrawalToEigenLayer(nodeToAssets[i], nodeToAmounts[i]);

            unchecked {
                ++i;
            }
        }

        address[] memory supportedAssets = eigenpieConfig.getSupportedAssetList();
        for (uint256 i = 0; i < supportedAssets.length;) {
            bytes32 assetToEpochKey = keccak256(abi.encodePacked(supportedAssets[i], epochNumber));
            WithdrawalSum memory withdrawalSum = withdrawalSums[assetToEpochKey];
            if (withdrawalSum.assetTotalToWithdrawAmt != withdrawalSum.assetTotalWithdrawQueued) {
                revert NotWithdrawAllQueuedRequest();
            }

            if (withdrawalSum.assetTotalWithdrawQueued > 0) {
                address receipt = eigenpieConfig.mLRTReceiptByAsset(supportedAssets[i]);
                IMintableERC20(receipt).burnFrom(address(this), withdrawalSum.mLRTTotalToBurn);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Triggers stopped state. Contract must not be paused.
    function pause() external onlyEigenpieManager {
        _pause();
    }

    /// @dev Returns to normal state. Contract must be paused
    function unpause() external onlyDefaultAdmin {
        _unpause();
    }

    function updateWithdrawalScheduleCleanUpThreshold(uint256 _newThreshold) external onlyDefaultAdmin {
        require(_newThreshold > 0, "New threshold must be greater than zero");
        withdrawalscheduleCleanUp = _newThreshold;
        emit VestingWithdrawalCleanUpThresholdUpdated(_newThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    function _cleanUpWithdrawalSchedules(
        address[] memory assets,
        uint256[] memory claimedWithdrawalSchedules
    )
        internal
    {
        for (uint256 i = 0; i < assets.length;) {
            bytes32 userToAsset = userToAssetKey(msg.sender, assets[i]);
            UserWithdrawalSchedule[] storage schedules = withdrawalSchedules[userToAsset];

            if (claimedWithdrawalSchedules[i] >= withdrawalscheduleCleanUp) {
                for (uint256 j = 0; j < schedules.length - claimedWithdrawalSchedules[i];) {
                    schedules[j] = schedules[j + claimedWithdrawalSchedules[i]];

                    unchecked {
                        ++j;
                    }
                }

                while (claimedWithdrawalSchedules[i] > 0) {
                    schedules.pop();
                    claimedWithdrawalSchedules[i]--;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    function _calculateAmounts(
        address _user,
        address[] memory _assets
    )
        internal
        view
        returns (uint256[] memory queuedAmounts, uint256[] memory claimableAmounts, uint256[] memory claimedAmounts)
    {
        queuedAmounts = new uint256[](_assets.length);
        claimableAmounts = new uint256[](_assets.length);
        claimedAmounts = new uint256[](_assets.length);

        for (uint256 i = 0; i < _assets.length;) {
            bytes32 key = userToAssetKey(_user, _assets[i]);
            uint256 totalAmount = 0;
            uint256 totalClaimed = 0;
            uint256 totalClaimable = 0;

            UserWithdrawalSchedule[] memory schedules = withdrawalSchedules[key];
            for (uint256 j = 0; j < schedules.length;) {
                UserWithdrawalSchedule memory schedule = schedules[j];
                bool claimable = (schedule.endTime <= block.timestamp) && schedule.claimedAmt == 0;
                if (claimable) totalClaimable += schedule.queuedWithdrawLSTAmt;
                totalAmount += schedule.queuedWithdrawLSTAmt;
                totalClaimed += schedule.claimedAmt;

                unchecked {
                    ++j;
                }
            }

            queuedAmounts[i] = totalAmount;
            claimableAmounts[i] = totalClaimable;
            claimedAmounts[i] = totalClaimed;

            unchecked {
                ++i;
            }
        }

        return (queuedAmounts, claimableAmounts, claimedAmounts);
    }

    function _getKey(address _user, address _asset, uint256 _epochTime, bool _isUser) internal pure returns (bytes32) {
        if (_isUser) {
            return keccak256(abi.encodePacked(_user, _asset));
        } else {
            return keccak256(abi.encodePacked(_asset, _epochTime));
        }
    }
}
