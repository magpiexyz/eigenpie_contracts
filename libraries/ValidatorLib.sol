// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EigenpieConstants } from "../utils/EigenpieConstants.sol";
import { BeaconChainProofs } from "../utils/external/BeaconChainProofs.sol";
import { ISSVClusters } from "../interfaces/ssvNetwork/ISSVClusters.sol";
import { ISSVNetworkCore } from "../interfaces/ssvNetwork/ISSVNetworkCore.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBeaconDepositContract } from "../interfaces/IBeaconDepositContract.sol";
import { IDelegationManager } from "../interfaces/eigenlayer/IDelegationManager.sol";
import { INodeDelegator } from "../interfaces/INodeDelegator.sol";
import { IStrategy } from "../interfaces/eigenlayer/IStrategy.sol";
import { IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";
import { IEigenPod } from "../interfaces/eigenlayer/IEigenPodManager.sol";

// A library that handles the operations associated with validators, like registration and deposit handling. This
// library will encapsulate the logic for interactions with the Beacon chain and SSV network.
library ValidatorLib {
    using SafeERC20 for IERC20;

    event WithdrawalQueuedToEigenLayer(
        bytes32[] withdrawalRoot, IStrategy[] strategies, address[] assets, uint256[] amounts, uint256 blockNumber
    );

    function makeBeaconDeposit(
        bytes[] memory publicKeys,
        bytes[] memory signatures,
        bytes32[] memory depositDataRoots,
        IEigenpieConfig eigenpieConfig,
        address eigenPod
    )
        external
    {
        // sanity checks
        uint256 count = depositDataRoots.length;
        if (count == 0) revert INodeDelegator.AtLeastOneValidator();
        if (count >= EigenpieConstants.MAX_VALIDATORS) {
            revert INodeDelegator.MaxValidatorsInput();
        }
        if (publicKeys.length != count) {
            revert INodeDelegator.PublicKeyNotMatch();
        }
        if (signatures.length != count) {
            revert INodeDelegator.SignaturesNotMatch();
        }

        address depositContract = eigenpieConfig.getContract(EigenpieConstants.BEACON_DEPOSIT);
        bytes memory withdrawalCredentials = getEigenPodwithdrawCredential(eigenPod);

        for (uint256 i = 0; i < count;) {
            IBeaconDepositContract(depositContract).deposit{ value: EigenpieConstants.DEPOSIT_AMOUNT }(
                publicKeys[i], withdrawalCredentials, signatures[i], depositDataRoots[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Registers new validators on the SSV Network
    function bulkRegisterValidator(
        bytes[] calldata publicKeys,
        uint64[] calldata operatorIds,
        bytes[] calldata sharesData,
        uint256 amount,
        ISSVNetworkCore.Cluster memory cluster,
        IEigenpieConfig eigenpieConfig
    )
        external
    {
        address ssvToken = eigenpieConfig.getContract(EigenpieConstants.SSV_TOKEN);
        address ssvNetwork = eigenpieConfig.getContract(EigenpieConstants.SSVNETWORK_ENTRY);

        IERC20(ssvToken).approve(ssvNetwork, amount);
        ISSVClusters(ssvNetwork).bulkRegisterValidator(publicKeys, operatorIds, sharesData, amount, cluster);
    }

    function getEigenPodwithdrawCredential(address eigenPod) public pure returns (bytes memory) {
        if (eigenPod == address(0)) revert INodeDelegator.EigenPodExisted();

        bytes memory withdrawalCredentials = abi.encodePacked(hex"010000000000000000000000", eigenPod);

        return withdrawalCredentials;
    }

    function verifyWithdrawalCredentials(
        IEigenPod eigenPod,
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata withdrawalCredentialProofs,
        bytes32[][] calldata validatorFields
    )
        external
        returns (uint256 stakedButNotVerifiedEth)
    {
        eigenPod.verifyWithdrawalCredentials(
            oracleTimestamp, stateRootProof, validatorIndices, withdrawalCredentialProofs, validatorFields
        );

        // Decrement the staked but not verified ETH
        for (uint256 i = 0; i < validatorFields.length;) {
            uint64 validatorCurrentBalanceGwei = BeaconChainProofs.getEffectiveBalanceGwei(validatorFields[i]);
            stakedButNotVerifiedEth += (validatorCurrentBalanceGwei * EigenpieConstants.GWEI_TO_WEI);

            unchecked {
                ++i;
            }
        }
    }

    function queueWithdrawalToEigenLayer(
        IEigenpieConfig eigenpieConfig,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory lstToWithdraw
    )
        external
    {
        address delegationManagerAddr = eigenpieConfig.getContract(EigenpieConstants.EIGEN_DELEGATION_MANAGER);

        IDelegationManager.QueuedWithdrawalParams[] memory withdrawParams =
            new IDelegationManager.QueuedWithdrawalParams[](1);
        withdrawParams[0].strategies = new IStrategy[](assets.length);
        withdrawParams[0].shares = new uint256[](assets.length);
        withdrawParams[0].withdrawer = address(this);

        for (uint256 i = 0; i < assets.length;) {
            address strategy = eigenpieConfig.assetStrategy(assets[i]);
            withdrawParams[0].strategies[i] = IStrategy(strategy);
            withdrawParams[0].shares[i] = IStrategy(strategy).underlyingToShares(lstToWithdraw[i]);

            unchecked {
                ++i;
            }
        }

        bytes32[] memory withdrawalRoot = IDelegationManager(delegationManagerAddr).queueWithdrawals(withdrawParams);

        emit INodeDelegator.WithdrawalQueuedToEigenLayer(
            withdrawalRoot, withdrawParams[0].strategies, assets, amounts, block.number
        );
    }

    function completeAssetWithdrawalFromEigenLayer(
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens,
        address recipient,
        address delegationManagerAddr
    )
        external
    {
        uint256[] memory beforeAmounts = new uint256[](tokens.length);
        // Record the balance before the withdrawal
        for (uint256 i = 0; i < tokens.length;) {
            beforeAmounts[i] = tokens[i].balanceOf(address(this));

            unchecked {
                ++i;
            }
        }

        // Complete the queued withdrawal
        IDelegationManager(delegationManagerAddr).completeQueuedWithdrawal(
            withdrawal, tokens, middlewareTimesIndex, receiveAsTokens
        );

        // Transfer the withdrawn amounts to the recipient
        for (uint256 i = 0; i < tokens.length;) {
            uint256 afterBalance = tokens[i].balanceOf(address(this));
            uint256 difference = afterBalance - beforeAmounts[i];
            if (difference > 0) {
                IERC20(tokens[i]).safeTransfer(recipient, difference);
            }
            unchecked {
                ++i;
            }
        }
    }
}
