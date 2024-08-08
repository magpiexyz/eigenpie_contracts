// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "./utils/UtilLib.sol";
import { TransferHelper } from "./utils/TransferHelper.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { EigenpieConstants } from "./utils/EigenpieConstants.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "./utils/EigenpieConfigRoleChecker.sol";
import { IDelegationManager } from "./interfaces/eigenlayer/IDelegationManager.sol";
import { IMintableERC20 } from "./interfaces/IMintableERC20.sol";

import { IStrategyManager } from "./interfaces/eigenlayer/IStrategyManager.sol";
import { INodeDelegator } from "./interfaces/INodeDelegator.sol";
import { IMLRT } from "./interfaces/IMLRT.sol";
import { IStrategy } from "./interfaces/eigenlayer/IStrategy.sol";
import { BeaconChainProofs } from "./utils/external/BeaconChainProofs.sol";
import { IEigenPodManager, IEigenPod } from "./interfaces/eigenlayer/IEigenPodManager.sol";
import { IBeaconDepositContract } from "./interfaces/IBeaconDepositContract.sol";
import { ISignatureUtils } from "./interfaces/eigenlayer/ISignatureUtils.sol";

import { ISSVClusters } from "./interfaces/ssvNetwork/ISSVClusters.sol";
import { ISSVNetwork } from "./interfaces/ssvNetwork/ISSVNetwork.sol";
import { ISSVNetworkCore } from "./interfaces/ssvNetwork/ISSVNetworkCore.sol";

import { ValidatorLib } from "./libraries/ValidatorLib.sol";
import { AssetManagementLib } from "./libraries/AssetManagementLib.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title Whitelisted NodeDelegator Contract
/// @notice The contract that handles the depositing of assets into strategies
contract WLNodedelegator is
    INodeDelegator,
    EigenpieConfigRoleChecker,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    struct RewardDest {
        uint256 value; // allocation denominated by DENOMINATOR
        address to; // allocation denominated by DENOMINATOR
    }

    IEigenPod public eigenPod;
    /// @dev Tracks the balance staked to validators and has yet to have the credentials verified with EigenLayer.
    /// call verifyWithdrawalCredentials to verify the validator credentials on EigenLayer
    uint256 public stakedButNotVerifiedEth;
    address public delegateAddress;
    address public client;

    RewardDest[] public rewardDests;

    // error
    error OnlyClient();
    error NotAllowedCaller();
    error NotSupported();
    error InvalidFeePercentage();
    error InvalidIndex();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    fallback() external {
        revert InvalidCall();
    }

    modifier onlyClient() {
        if (msg.sender != client) revert OnlyClient();
        _;
    }

    modifier onlyClientOrManager() {
        bool isClient = (msg.sender == client);
        bool isManager = IAccessControl(address(eigenpieConfig)).hasRole(EigenpieConstants.MANAGER, msg.sender);

        if (!(isClient || isManager)) revert NotAllowedCaller();
        _;
    }

    receive() external payable {
        address dwr = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_DWR);
        // CL rewards
        if (msg.sender == dwr) {
            uint256 length = rewardDests.length;

            for (uint256 i; i < length;) {
                RewardDest memory dest = rewardDests[i];
                uint256 toSendAmount = msg.value * dest.value / EigenpieConstants.DENOMINATOR;

                TransferHelper.safeTransferETH(dest.to, toSendAmount);

                unchecked {
                    ++i;
                }
            }
        }

        // TODO will have to deal with full withdraw
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfigAddr Eigenpie config address
    function initialize(address eigenpieConfigAddr, address _client) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfigAddr);
        __Pausable_init();
        __ReentrancyGuard_init();
        client = _client;

        eigenpieConfig = IEigenpieConfig(eigenpieConfigAddr);

        emit UpdatedEigenpieConfig(eigenpieConfigAddr);
    }

    /*//////////////////////////////////////////////////////////////
                            Read functions
    //////////////////////////////////////////////////////////////*/

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

    /// @dev Returns the balance of an asset that the node delegator has deposited into the strategy
    /// @param asset the asset to get the balance of
    /// @return stakedBalance the balance of the asset
    function getAssetBalance(address asset) external view override returns (uint256) {
        return AssetManagementLib.getAssetBalance(eigenpieConfig, asset, stakedButNotVerifiedEth);
    }

    function getEthBalance() external view override returns (uint256) {
        // TODO: Once withdrawals are enabled, allow this to handle pending withdraws
        IEigenPodManager eigenPodManager =
            IEigenPodManager(eigenpieConfig.getContract(EigenpieConstants.EIGENPOD_MANAGER));
        return AssetManagementLib.getEthBalance(eigenPodManager, stakedButNotVerifiedEth, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            Write functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits an asset lying in this NDC into its strategy
    /// @dev only supported assets can be deposited and only called by the Eigenpie manager
    /// @param asset the asset to deposit
    function depositAssetIntoStrategy(
        address asset,
        uint256 lstAmount
    )
        external
        whenNotPaused
        nonReentrant
        onlySupportedAsset(asset)
        onlyClient
    {
        if (lstAmount == 0) revert InvalidAmount();
        AssetManagementLib.depositAssetIntoStrategy(asset, eigenpieConfig, lstAmount, true);
        // mint mlrt to the client
        _mintMLRT(asset, lstAmount);
    }

    /// @dev Sets the address to delegate tokens to in EigenLayer -- THIS CAN ONLY BE SET ONCE
    function setDelegateAddress(
        address _delegateAddress,
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    )
        external
        nonReentrant
        onlyClient
    {
        UtilLib.checkNonZeroAddress(_delegateAddress);
        if (address(delegateAddress) != address(0x0)) revert DelegateAddressAlreadySet();

        delegateAddress = _delegateAddress;

        address delegationManagerAddr = eigenpieConfig.getContract(EigenpieConstants.EIGEN_DELEGATION_MANAGER);
        IDelegationManager(delegationManagerAddr).delegateTo(_delegateAddress, approverSignatureAndExpiry, approverSalt);

        emit DelegationAddressUpdated(_delegateAddress);
    }

    function queueWithdrawalToEigenLayer(
        address[] memory assets,
        uint256[] memory mlrtAmounts
    )
        external
        nonReentrant
        onlyClient
    {
        uint256[] memory lstToWithdraw = _burnMLRT(assets, mlrtAmounts);
        ValidatorLib.queueWithdrawalToEigenLayer(eigenpieConfig, assets, mlrtAmounts, lstToWithdraw);
    }

    function completeAssetWithdrawalFromEigenLayer(
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex
    )
        external
        nonReentrant
        onlyClient
    {
        address delegationManagerAddr = eigenpieConfig.getContract(EigenpieConstants.EIGEN_DELEGATION_MANAGER);
        ValidatorLib.completeAssetWithdrawalFromEigenLayer(
            withdrawal, tokens, middlewareTimesIndex, true, msg.sender, delegationManagerAddr
        );
    }

    /// @dev Triggers stopped state. Contract must not be paused.
    function pause() external onlyEigenpieManager {
        _pause();
    }

    /// @dev Returns to normal state. Contract must be paused
    function unpause() external onlyDefaultAdmin {
        _unpause();
    }

    function setupValidators(DepositData calldata depositData) external payable whenNotPaused nonReentrant onlyClient {
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
        onlyClient
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
        onlyClientOrManager
    {
        stakedButNotVerifiedEth -= ValidatorLib.verifyWithdrawalCredentials(
            eigenPod, oracleTimestamp, stateRootProof, validatorIndices, withdrawalCredentialProofs, validatorFields
        );
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
        onlyClientOrManager
    {
        eigenPod.verifyAndProcessWithdrawals(
            oracleTimestamp, stateRootProof, withdrawalProofs, validatorFieldsProofs, validatorFields, withdrawalFields
        );
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
        onlyClientOrManager
    {
        eigenPod.withdrawNonBeaconChainETHBalanceWei(recipient, amountToWithdraw);
    }

    //The DepositManager will be the pod owner in the EigenPodManager contract
    function createEigenPod() external override onlyClientOrManager {
        if (address(eigenPod) != address(0)) {
            revert EigenPodExisted();
        }

        IEigenPodManager eigenPodManager = AssetManagementLib.getEigenPodManager(eigenpieConfig);
        IEigenPodManager(eigenPodManager).createPod();

        eigenPod = eigenPodManager.getPod(address(this));

        emit EigenPodCreated(address(eigenPod));
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
        onlyClient
    {
        ValidatorLib.bulkRegisterValidator(publicKeys, operatorIds, sharesData, amount, cluster, eigenpieConfig);
    }

    /// @notice Fires the exit event for a set of validators
    function bulkExitValidator(bytes[] calldata publicKeys, uint64[] calldata operatorIds) external onlyClient {
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
        onlyClient
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
        onlyClientOrManager
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
        onlyClientOrManager
    {
        address ssvNetwork = eigenpieConfig.getContract(EigenpieConstants.SSVNETWORK_ENTRY);
        ISSVClusters(ssvNetwork).withdraw(operatorIds, tokenAmount, cluster);
    }

    /*//////////////////////////////////////////////////////////////
                            Admin functions
    //////////////////////////////////////////////////////////////*/

    function addRewardDestination(uint256 _value, address _to) external onlyDefaultAdmin {
        if (_value > EigenpieConstants.DENOMINATOR) revert InvalidFeePercentage();
        UtilLib.checkNonZeroAddress(_to);

        rewardDests.push(RewardDest({ value: _value, to: _to }));
    }

    function setRewardDestination(uint256 _index, uint256 _value, address _to) external onlyDefaultAdmin {
        if (_index >= rewardDests.length) revert InvalidIndex();
        if (_value > EigenpieConstants.DENOMINATOR) revert InvalidFeePercentage();
        UtilLib.checkNonZeroAddress(_to);

        RewardDest storage dest = rewardDests[_index];
        dest.value = _value;
        dest.to = _to;
    }

    function removeRewardDestination(uint256 _index) external onlyDefaultAdmin {
        if (_index >= rewardDests.length) revert InvalidIndex();

        for (uint256 i = _index; i < rewardDests.length - 1; i++) {
            rewardDests[i] = rewardDests[i + 1];
        }

        rewardDests.pop();
    }

    /*//////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

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

    function _mintMLRT(address asset, uint256 amount) internal {
        address receipt = eigenpieConfig.mLRTReceiptByAsset(asset);
        uint256 rate = IMLRT(receipt).exchangeRateToLST();
        uint256 toMint = ((amount * 1 ether) / rate);

        IMintableERC20(receipt).mint(msg.sender, toMint);
    }

    function _burnMLRT(
        address[] memory assets,
        uint256[] memory mlrtAmounts
    )
        internal
        returns (uint256[] memory lstToWithdraw)
    {
        lstToWithdraw = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length;) {
            address receipt = eigenpieConfig.mLRTReceiptByAsset(assets[i]);
            uint256 rate = IMLRT(receipt).exchangeRateToLST();
            lstToWithdraw[i] = mlrtAmounts[i] * rate / 1 ether;

            IMintableERC20(receipt).burnFrom(msg.sender, mlrtAmounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
            Override functions to make compiler happy
    //////////////////////////////////////////////////////////////*/
    function depositAssetIntoStrategy(address asset) external override {
        revert NotSupported();
    }

    function maxApproveToEigenStrategyManager(address asset) external override {
        revert NotSupported();
    }
}
