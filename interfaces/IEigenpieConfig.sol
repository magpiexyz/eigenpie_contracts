// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

interface IEigenpieConfig {
    // Errors
    error ValueAlreadyInUse();
    error AssetAlreadySupported();
    error AssetNotSupported();
    error CallerNotEigenpieConfigAdmin();
    error CallerNotEigenpieConfigManager();
    error CallerNotEigenpieConfigOracle();
    error CallerNotEigenpieConfigOracleAdmin();
    error CallerNotEigenpieConfigPriceProvider();
    error CallerNotEigenpieConfigMinter();
    error CallerNotEigenpieConfigBurner();
    error CallerNotEigenpieConfigAllowedRole(string role);
    error CallerNotEigenpieConfigAllowedBot();

    // Events
    event SetContract(bytes32 key, address indexed contractAddr);
    event AddedNewSupportedAsset(address indexed asset, address indexed receipt, uint256 depositLimit);
    event ReceiptTokenUpdated(address indexed asset, address indexed receipt);
    event RemovedSupportedAsset(address indexed asset);
    event AssetDepositLimitUpdate(address indexed asset, uint256 depositLimit);
    event AssetStrategyUpdate(address indexed asset, address indexed strategy);
    event AssetBoostUpdate(address indexed asset, uint256 newBoost);
    event ReferralUpdate(address indexed me, address indexed myReferral);

    // methods
    function baseGasAmountSpent() external returns (uint256);

    function assetStrategy(address asset) external view returns (address);

    function boostByAsset(address) external view returns (uint256);

    function mLRTReceiptByAsset(address) external view returns (address);

    function isSupportedAsset(address asset) external view returns (bool);

    function getContract(bytes32 contractId) external view returns (address);

    function getSupportedAssetList() external view returns (address[] memory);

    function depositLimitByAsset(address asset) external view returns (uint256);
}
