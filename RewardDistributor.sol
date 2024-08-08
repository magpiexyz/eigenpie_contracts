// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "./utils/UtilLib.sol";
import { TransferHelper } from "./utils/TransferHelper.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EigenpieConstants } from "./utils/EigenpieConstants.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "./utils/EigenpieConfigRoleChecker.sol";

import { IRewardDistributor } from "./interfaces/IRewardDistributor.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract RewardDistributor is
    IRewardDistributor,
    EigenpieConfigRoleChecker,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    RewardDestinations[] public rewardDests;

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfigAddr Eigenpie config address
    function initialize(address eigenpieConfigAddr) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfigAddr);
        __Pausable_init();
        __ReentrancyGuard_init();

        eigenpieConfig = IEigenpieConfig(eigenpieConfigAddr);
        emit UpdatedEigenpieConfig(eigenpieConfigAddr);
    }

    receive() external payable nonReentrant {
        _forwardETH();
    }

    // TODO, will have to handle ERC20 if reward in LST form
    function forwardRewards() external payable nonReentrant whenNotPaused onlyEigenpieManager {
        _forwardETH();
    }

    function _forwardETH() internal {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            return;
        }

        uint256 length = rewardDests.length;

        for (uint256 i; i < length;) {
            RewardDestinations memory dest = rewardDests[i];
            uint256 toSendAmount = balance * dest.value / EigenpieConstants.DENOMINATOR;

            if (dest.needWrap) {
                // TODO will need to handle wrap as Weth
                // TODO will ned to check if isAddress and queue reward to rewarder
            } else {
                TransferHelper.safeTransferETH(dest.to, toSendAmount);
            }

            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            Admin functions
    //////////////////////////////////////////////////////////////*/

    function addRewardDestination(
        uint256 _value,
        address _to,
        bool _isAddress,
        bool _needWrap
    )
        external
        onlyDefaultAdmin
    {
        if (_value > EigenpieConstants.DENOMINATOR) revert InvalidFeePercentage();
        UtilLib.checkNonZeroAddress(_to);

        rewardDests.push(RewardDestinations({ value: _value, to: _to, isAddress: _isAddress, needWrap: _needWrap }));
        emit RewardDestinationAdded(rewardDests.length - 1, _value, _to, _isAddress, _needWrap);
    }

    function setRewardDestination(
        uint256 _index,
        uint256 _value,
        address _to,
        bool _isAddress,
        bool _needWrap
    )
        external
        onlyDefaultAdmin
    {
        if (_index >= rewardDests.length) revert InvalidIndex();
        if (_value > EigenpieConstants.DENOMINATOR) revert InvalidFeePercentage();
        UtilLib.checkNonZeroAddress(_to);

        RewardDestinations storage dest = rewardDests[_index];
        dest.value = _value;
        dest.to = _to;
        dest.isAddress = _isAddress;
        dest.needWrap = _needWrap;
        emit RewardDestinationUpdated(_index, _value, _to, _isAddress, _needWrap);
    }

    function removeRewardDestination(uint256 _index) external onlyDefaultAdmin {
        if (_index >= rewardDests.length) revert InvalidIndex();

        for (uint256 i = _index; i < rewardDests.length - 1; i++) {
            rewardDests[i] = rewardDests[i + 1];
        }
        rewardDests.pop();
        emit RewardDestinationRemoved(_index);
    }

    /// @dev Triggers stopped state. Contract must not be paused.
    function pause() external onlyEigenpieManager {
        _pause();
    }

    /// @dev Returns to normal state. Contract must be paused
    function unpause() external onlyDefaultAdmin {
        _unpause();
    }
}
