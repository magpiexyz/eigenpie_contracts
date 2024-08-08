// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "./utils/UtilLib.sol";
import { BeaconChainProofs } from "./utils/external/BeaconChainProofs.sol";
import { TransferHelper } from "./utils/TransferHelper.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EigenpieConstants } from "./utils/EigenpieConstants.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "./utils/EigenpieConfigRoleChecker.sol";

import { INodeDelegator } from "./interfaces/INodeDelegator.sol";
import { IStrategy } from "./interfaces/eigenlayer/IStrategy.sol";
import { IDelegationManager } from "./interfaces/eigenlayer/IDelegationManager.sol";

import { IStrategyManager } from "./interfaces/eigenlayer/IStrategyManager.sol";
import { ISignatureUtils } from "./interfaces/eigenlayer/ISignatureUtils.sol";
import { IEigenPodManager, IEigenPod } from "./interfaces/eigenlayer/IEigenPodManager.sol";
import { IBeaconDepositContract } from "./interfaces/IBeaconDepositContract.sol";

import { ISSVClusters } from "./interfaces/ssvNetwork/ISSVClusters.sol";
import { ISSVNetwork } from "./interfaces/ssvNetwork/ISSVNetwork.sol";
import { ISSVNetworkCore } from "./interfaces/ssvNetwork/ISSVNetworkCore.sol";

import { ValidatorLib } from "./libraries/ValidatorLib.sol";
import { AssetManagementLib } from "./libraries/AssetManagementLib.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title NodeDelegator Contract
/// @notice The contract that handles the depositing of assets into strategies
contract NodeDelegator is INodeDelegator, EigenpieConfigRoleChecker, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IEigenPod public eigenPod;
    /// @dev Tracks the balance staked to validators and has yet to have the credentials verified with EigenLayer.
    /// call verifyWithdrawalCredentials to verify the validator credentials on EigenLayer
    uint256 public stakedButNotVerifiedEth;
    // operator that the Node delegator delegates to
    address public delegateAddress;

    /// @dev A mapping to track how much gas was spent by an address
    mapping(address => uint256) public adminGasSpentInWei;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    fallback() external {
        revert InvalidCall();
    }

    receive() external payable {
        address eigenStaking = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_STAKING);
        // If Eth from Eigenstaking, then should stay waiting to be restaked;
        if (msg.sender == eigenStaking) {
            return;
        }

        uint256 gasRefunded;
        address dwr = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_DWR);
        // If Eth from dwr, then is partial withdraw of CL reward
        if (msg.sender == dwr && adminGasSpentInWei[tx.origin] > 0) {
            gasRefunded = _refundGas();

            // If no funds left, return
            if (msg.value == gasRefunded) {
                return;
            }
        }

        // Forward remaining balance to rewarDistributor.
        // Any random eth transfer to this contract will also be treated as reward.
        address rewarDistributor = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_REWADR_DISTRIBUTOR);
        TransferHelper.safeTransferETH(rewarDistributor, msg.value - gasRefunded);

        emit RewardsForwarded(rewarDistributor, msg.value);
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

    modifier onlyEigenpieStaking() {
        address eigenpieStaking = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_STAKING);
        if (msg.sender != eigenpieStaking) revert InvalidCaller();
        _;
    }

    modifier onlyWithdrawManager() {
        address eigenpieStaking = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_WITHDRAW_MANAGER);
        if (msg.sender != eigenpieStaking) revert InvalidCaller();
        _;
    }

    /// @notice Fetches balance of all assets staked in eigen layer through this contract
    /// @return assets the assets that the node delegator has deposited into strategies and eth native staking.
    /// @return assetBalances the balances of the assets that the node delegator has deposited into strategies
    function getAssetBalances()
        external
        view
        override
        returns (address[] memory assets, uint256[] memory assetBalances)
    {
        address eigenlayerStrategyManagerAddress = eigenpieConfig.getContract(EigenpieConstants.EIGEN_STRATEGY_MANAGER);
        return AssetManagementLib.getAssetBalances(
            eigenlayerStrategyManagerAddress, stakedButNotVerifiedEth, eigenpieConfig
        );
    }

    function getEigenPod() external view returns (address) {
        return address(eigenPod);
    }

    /// @dev Returns the balance of an asset that the node delegator has deposited into the strategy
    /// @param asset the asset to get the balance of
    /// @return stakedBalance the balance of the asset
    function getAssetBalance(address asset) external view override returns (uint256) {
        return AssetManagementLib.getAssetBalance(eigenpieConfig, asset, stakedButNotVerifiedEth);
    }

    /// @dev Gets the amount of ETH staked in the EigenLayer
    function getEthBalance() external view returns (uint256) {
        // TODO: Once withdrawals are enabled, allow this to handle pending withdraws
        IEigenPodManager eigenPodManager = AssetManagementLib.getEigenPodManager(eigenpieConfig);
        return AssetManagementLib.getEthBalance(eigenPodManager, stakedButNotVerifiedEth, address(this));
    }

    /// @dev Triggers stopped state. Contract must not be paused.
    function pause() external onlyEigenpieManager {
        _pause();
    }

    /// @dev Returns to normal state. Contract must be paused
    function unpause() external onlyDefaultAdmin {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            EigenLayer functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Approves the maximum amount of an asset to the eigen strategy manager
    /// @dev only supported assets can be deposited and only called by the Eigenpie manager
    /// @param asset the asset to deposit
    function maxApproveToEigenStrategyManager(address asset)
        external
        override
        onlySupportedAsset(asset)
        onlyEigenpieManager
    {
        address eigenlayerStrategyManagerAddress = eigenpieConfig.getContract(EigenpieConstants.EIGEN_STRATEGY_MANAGER);
        IERC20(asset).safeApprove(eigenlayerStrategyManagerAddress, type(uint256).max);
    }

    /// @notice Deposits an asset lying in this NDC into its strategy
    /// @dev only supported assets can be deposited and only called by the Eigenpie manager
    /// @param asset the asset to deposit
    function depositAssetIntoStrategy(address asset)
        external
        override
        whenNotPaused
        nonReentrant
        onlySupportedAsset(asset)
        onlyAllowedBot
    {
        AssetManagementLib.depositAssetIntoStrategy(asset, eigenpieConfig, 0, false);
    }

    /// @dev Sets the address to delegate tokens to in EigenLayer -- THIS CAN ONLY BE SET ONCE
    function setDelegateAddress(
        address _delegateAddress,
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    )
        external
        nonReentrant
        onlyEigenpieManager
    {
        UtilLib.checkNonZeroAddress(_delegateAddress);
        if (address(delegateAddress) != address(0x0)) revert DelegateAddressAlreadySet();

        delegateAddress = _delegateAddress;

        address delegationManagerAddr = eigenpieConfig.getContract(EigenpieConstants.EIGEN_DELEGATION_MANAGER);
        IDelegationManager(delegationManagerAddr).delegateTo(delegateAddress, approverSignatureAndExpiry, approverSalt);

        emit DelegationAddressUpdated(_delegateAddress);
    }

    function setupValidators(DepositData calldata depositData)
        external
        payable
        whenNotPaused
        nonReentrant
        onlyAllowedBot
    {
        _makeBeaconDeposit(depositData.publicKeys, depositData.signatures, depositData.depositDataRoots);
    }

    function setupSSVNetwork(
        DepositData calldata depositData,
        SSVPayload calldata ssvPayload
    )
        external
        payable
        whenNotPaused
        nonReentrant
        onlyAllowedBot
    {
        _makeBeaconDeposit(depositData.publicKeys, depositData.signatures, depositData.depositDataRoots);
        ValidatorLib.bulkRegisterValidator(
            depositData.publicKeys,
            ssvPayload.operatorIds,
            ssvPayload.sharesData,
            ssvPayload.amount,
            ssvPayload.cluster,
            eigenpieConfig
        );
    }

    /// @dev Verifies the withdrawal credentials for a withdrawal
    /// This will allow the EigenPodManager to verify the withdrawal credentials and credit the Node delegators with
    /// shares
    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata withdrawalCredentialProofs,
        bytes32[][] calldata validatorFields
    )
        external
        whenNotPaused
        onlyAllowedBot
    {
        uint256 gasBefore = gasleft();
        stakedButNotVerifiedEth -= ValidatorLib.verifyWithdrawalCredentials(
            eigenPod, oracleTimestamp, stateRootProof, validatorIndices, withdrawalCredentialProofs, validatorFields
        );
        // update the gas spent for RestakeAdmin
        _recordGas(gasBefore);
    }

    /**
     * @notice  Verify many Withdrawals and process them in the EigenPod
     * @dev     For each withdrawal (partial or full), verify it in the EigenPod
     */
    function verifyAndProcessWithdrawals(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        BeaconChainProofs.WithdrawalProof[] calldata withdrawalProofs,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields,
        bytes32[][] calldata withdrawalFields
    )
        external
        whenNotPaused
        onlyAllowedBot
    {
        uint256 gasBefore = gasleft();

        eigenPod.verifyAndProcessWithdrawals(
            oracleTimestamp, stateRootProof, withdrawalProofs, validatorFieldsProofs, validatorFields, withdrawalFields
        );
        // update the gas spent for RestakeAdmin
        _recordGas(gasBefore);
    }

    /**
     * @notice  Pull out any ETH in the EigenPod that is not from the beacon chain
     * @dev     Only callable by admin
     * @param   recipient  Where to send the ETH
     * @param   amountToWithdraw  Amount to pull out
     */
    function withdrawNonBeaconChainETHBalanceWei(
        address recipient,
        uint256 amountToWithdraw
    )
        external
        whenNotPaused
        onlyEigenpieManager
    {
        eigenPod.withdrawNonBeaconChainETHBalanceWei(recipient, amountToWithdraw);
    }

    function queueWithdrawalToEigenLayer(
        address[] memory assets,
        uint256[] memory amounts
    )
        external
        whenNotPaused
        nonReentrant
        onlyWithdrawManager
    {
        ValidatorLib.queueWithdrawalToEigenLayer(eigenpieConfig, assets, amounts, amounts);
    }

    function completeAssetWithdrawalFromEigenLayer(
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    )
        external
        whenNotPaused
        nonReentrant
        onlyAllowedBot
    {
        address eigenpieWithdrawManager = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_WITHDRAW_MANAGER);
        address delegationManagerAddr = eigenpieConfig.getContract(EigenpieConstants.EIGEN_DELEGATION_MANAGER);
        ValidatorLib.completeAssetWithdrawalFromEigenLayer(
            withdrawal, tokens, middlewareTimesIndex, receiveAsTokens, eigenpieWithdrawManager, delegationManagerAddr
        );
    }

    //The DepositManager will be the pod owner in the EigenPodManager contract
    function createEigenPod() external override onlyDefaultAdmin {
        if (address(eigenPod) != address(0)) {
            revert EigenPodExisted();
        }

        IEigenPodManager eigenPodManager = AssetManagementLib.getEigenPodManager(eigenpieConfig);
        IEigenPodManager(eigenPodManager).createPod();

        eigenPod = eigenPodManager.getPod(address(this));

        emit EigenPodCreated(address(eigenPod));
    }

    function transferAssetToEigenStaking(address asset, uint256 amount) external onlyEigenpieManager {
        address eigenStaking = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_STAKING);
        TransferHelper.safeTransferToken(asset, eigenStaking, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            SSV Network functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Registers new validators on the SSV Network
    function bulkRegisterValidator(
        bytes[] calldata publicKeys,
        uint64[] calldata operatorIds,
        bytes[] calldata sharesData,
        uint256 amount,
        ISSVNetworkCore.Cluster memory cluster
    )
        external
        onlyEigenpieManager
    {
        ValidatorLib.bulkRegisterValidator(publicKeys, operatorIds, sharesData, amount, cluster, eigenpieConfig);
    }

    /// @notice Fires the exit event for a set of validators
    function bulkExitValidator(
        bytes[] calldata publicKeys,
        uint64[] calldata operatorIds
    )
        external
        onlyEigenpieManager
    {
        address ssvNetwork = eigenpieConfig.getContract(EigenpieConstants.SSVNETWORK_ENTRY);
        ISSVClusters(ssvNetwork).bulkExitValidator(publicKeys, operatorIds);
    }

    /// @notice Bulk removes a set of existing validators in the same cluster from the SSV Network
    /// @notice Reverts if publicKeys contains duplicates or non-existent validators
    function bulkRemoveValidator(
        bytes[] calldata publicKeys,
        uint64[] memory operatorIds,
        ISSVNetworkCore.Cluster memory cluster
    )
        external
        onlyEigenpieManager
    {
        address ssvNetwork = eigenpieConfig.getContract(EigenpieConstants.SSVNETWORK_ENTRY);
        ISSVClusters(ssvNetwork).bulkRemoveValidator(publicKeys, operatorIds, cluster);
    }

    function setFeeRecipientAddress(address feeRecipientAddress) external onlyEigenpieManager {
        address ssvNetwork = eigenpieConfig.getContract(EigenpieConstants.SSVNETWORK_ENTRY);
        ISSVNetwork(ssvNetwork).setFeeRecipientAddress(feeRecipientAddress);
    }

    function deposit(
        uint64[] memory operatorIds,
        uint256 amount,
        ISSVNetworkCore.Cluster memory cluster
    )
        external
        onlyEigenpieManager
    {
        address ssvNetwork = eigenpieConfig.getContract(EigenpieConstants.SSVNETWORK_ENTRY);
        ISSVClusters(ssvNetwork).deposit(address(this), operatorIds, amount, cluster);
    }

    function withdraw(
        uint64[] memory operatorIds,
        uint256 tokenAmount,
        ISSVNetworkCore.Cluster memory cluster
    )
        external
        onlyEigenpieManager
    {
        address ssvNetwork = eigenpieConfig.getContract(EigenpieConstants.SSVNETWORK_ENTRY);
        ISSVClusters(ssvNetwork).withdraw(operatorIds, tokenAmount, cluster);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice  Adds the amount of gas spent for an account
     * @dev     Tracks for later redemption from rewards coming from the DWR
     * @param   initialGas  .
     */
    function _recordGas(uint256 initialGas) internal {
        uint256 gasSpent = AssetManagementLib.calculateGasSpent(initialGas, eigenpieConfig, tx.gasprice);

        adminGasSpentInWei[msg.sender] += gasSpent;
        emit GasSpent(msg.sender, gasSpent);
    }

    /**
     * @notice  Send owed refunds to the admin
     * @dev     .
     * @return  uint256  .
     */
    function _refundGas() internal returns (uint256) {
        uint256 gasRefund = AssetManagementLib.calculateAndTransferRefundGas(tx.origin, adminGasSpentInWei[tx.origin]);
        // reset gas spent by admin
        adminGasSpentInWei[tx.origin] -= gasRefund;

        emit GasRefunded(tx.origin, gasRefund);
        return gasRefund;
    }

    function _makeBeaconDeposit(
        bytes[] memory publicKeys,
        bytes[] memory signatures,
        bytes32[] memory depositDataRoots
    )
        internal
    {
        ValidatorLib.makeBeaconDeposit(publicKeys, signatures, depositDataRoots, eigenpieConfig, address(eigenPod));
        stakedButNotVerifiedEth += publicKeys.length * EigenpieConstants.DEPOSIT_AMOUNT;
    }
}
