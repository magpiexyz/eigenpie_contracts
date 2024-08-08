// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { BeaconChainProofs } from "../utils/external/BeaconChainProofs.sol";
import { IEigenPod } from "./eigenlayer/IEigenPod.sol";
import { IDelegationManager } from "./IDelegationManager.sol";

interface IEigenPodManager {
    function createPod() external;

    function getPod(address podOwner) external view returns (IEigenPod);

    function podOwnerShares(address podOwner) external view returns (int256);

    function delegationManager() external view returns (IDelegationManager);
}

// interface IEigenPod {
//     /// @notice Called by the pod owner to withdraw the balance of the pod when `hasRestaked` is set to false
//     function withdrawBeforeRestaking() external;

//     function verifyWithdrawalCredentialsAndBalance(
//         uint64 oracleBlockNumber,
//         uint40 validatorIndex,
//         BeaconChainProofs.ValidatorFieldsAndBalanceProofs memory proofs,
//         bytes32[] calldata validatorFields
//     )
//         external;

//     function delayedWithdrawalRouter() external returns (address);
// }
