// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";
import { INodeDelegator } from "../interfaces/INodeDelegator.sol";
import { EigenpieConstants } from "../utils/EigenpieConstants.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IStrategyManager } from "../interfaces/eigenlayer/IStrategyManager.sol";
import { IStrategy } from "../interfaces/eigenlayer/IStrategy.sol";
import { IEigenPodManager } from "../interfaces/eigenlayer/IEigenPodManager.sol";
import { TransferHelper } from "../utils/TransferHelper.sol";
import { IMLRT } from "../interfaces/IMLRT.sol";
import { IMintableERC20 } from "../interfaces/IMintableERC20.sol";
import "../utils/UtilLib.sol";

library AssetManagementLib {
    using SafeERC20 for IERC20;

    event AssetDepositIntoStrategy(address indexed asset, address indexed strategy, uint256 depositAmount);

    function getAssetBalances(
        address eigenlayerStrategyManagerAddress,
        uint256 stakedButNotVerifiedEth,
        IEigenpieConfig eigenpieConfig
    )
        external
        view
        returns (address[] memory assets, uint256[] memory assetBalances)
    {
        IStrategyManager strategyManager = IStrategyManager(eigenlayerStrategyManagerAddress);
        (IStrategy[] memory strategies,) = strategyManager.getDeposits(address(this));

        uint256 strategiesLength = strategies.length;
        assets = new address[](strategiesLength + 1); // LSTs and native
        assetBalances = new uint256[](strategiesLength + 1); // LSTs and native

        IEigenPodManager eigenPodManager = getEigenPodManager(eigenpieConfig);
        assets[0] = EigenpieConstants.PLATFORM_TOKEN_ADDRESS;
        assetBalances[0] = getEthBalance(eigenPodManager, stakedButNotVerifiedEth, address(this));

        for (uint256 i = 0; i < strategiesLength;) {
            assets[i + 1] = address(IStrategy(strategies[i]).underlyingToken());
            assetBalances[i + 1] = IStrategy(strategies[i]).userUnderlyingView(address(this));
            unchecked {
                ++i;
            }
        }
        return (assets, assetBalances);
    }

    function getAssetBalance(
        IEigenpieConfig eigenpieConfig,
        address asset,
        uint256 stakedButNotVerifiedEth
    )
        external
        view
        returns (uint256)
    {
        if (UtilLib.isNativeToken(asset)) {
            IEigenPodManager eigenPodManager = getEigenPodManager(eigenpieConfig);
            return getEthBalance(eigenPodManager, stakedButNotVerifiedEth, address(this));
        } else {
            address strategy = eigenpieConfig.assetStrategy(asset);
            if (strategy == address(0)) {
                return 0;
            }
            return IStrategy(strategy).userUnderlyingView(address(this));
        }
    }

    function getEthBalance(
        IEigenPodManager eigenPodManager,
        uint256 stakedButNotVerifiedEth,
        address nodeDelegator
    )
        public
        view
        returns (uint256)
    {
        int256 podOwnerShares = eigenPodManager.podOwnerShares(nodeDelegator);
        return podOwnerShares < 0
            ? stakedButNotVerifiedEth - uint256(-podOwnerShares)
            : stakedButNotVerifiedEth + uint256(podOwnerShares);
    }

    function getEigenPodManager(IEigenpieConfig eigenpieConfig) public view returns (IEigenPodManager) {
        return IEigenPodManager(eigenpieConfig.getContract(EigenpieConstants.EIGENPOD_MANAGER));
    }

    function calculateRefundGas(uint256 adminGasSpentInWei) external returns (uint256) {
        uint256 gasRefund = msg.value >= adminGasSpentInWei ? adminGasSpentInWei : msg.value;
        return gasRefund;
    }

    function calculateAndTransferRefundGas(address origin, uint256 adminGasSpentInWei) external returns (uint256) {
        uint256 gasRefund = msg.value >= adminGasSpentInWei ? adminGasSpentInWei : msg.value;
        transferRefundGas(origin, gasRefund);
        return gasRefund;
    }

    function transferRefundGas(address origin, uint256 refundGas) internal {
        TransferHelper.safeTransferETH(origin, refundGas);
    }

    function calculateGasSpent(
        uint256 initialGas,
        IEigenpieConfig eigenpieConfig,
        uint256 gasPrice
    )
        external
        returns (uint256)
    {
        uint256 baseGasAmountSpent = eigenpieConfig.baseGasAmountSpent();
        uint256 gasSpent = (initialGas - gasleft() + baseGasAmountSpent) * gasPrice;
        return gasSpent;
    }

    function depositAssetIntoStrategy(
        address asset,
        IEigenpieConfig eigenpieConfig,
        uint256 lstAmount,
        bool isClient
    )
        external
    {
        address strategy = eigenpieConfig.assetStrategy(asset);
        if (strategy == address(0)) {
            revert INodeDelegator.StrategyIsNotSetForAsset();
        }

        IERC20 token = IERC20(asset);
        address eigenlayerStrategyManagerAddress = eigenpieConfig.getContract(EigenpieConstants.EIGEN_STRATEGY_MANAGER);

        // Transfer tokens from sender to this contract if lstAmount is specified
        if (lstAmount > 0) {
            token.safeTransferFrom(msg.sender, address(this), lstAmount);
        }

        uint256 depositAmount = isClient ? lstAmount : token.balanceOf(address(this));

        emit INodeDelegator.AssetDepositIntoStrategy(asset, strategy, depositAmount);

        if (depositAmount != 0) {
            uint256 oldAllowance = token.allowance(address(this), eigenlayerStrategyManagerAddress);
            if (oldAllowance < depositAmount) {
                if (oldAllowance > 0) {
                    // Reset approval to 0 if there is any existing allowance
                    token.safeApprove(eigenlayerStrategyManagerAddress, 0);
                }
                // Approve the new allowance
                token.safeApprove(eigenlayerStrategyManagerAddress, depositAmount);
            }
            IStrategyManager(eigenlayerStrategyManagerAddress).depositIntoStrategy(
                IStrategy(strategy), token, depositAmount
            );
        }
    }
}
