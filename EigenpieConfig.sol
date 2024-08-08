// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "./utils/UtilLib.sol";
import { EigenpieConstants } from "./utils/EigenpieConstants.sol";
import { IEigenpieConfig } from "./interfaces/IEigenpieConfig.sol";
import { IMLRT } from "./interfaces/IMLRT.sol";
import { IStrategy } from "./interfaces/eigenlayer/IStrategy.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title EigenpieConfig - Eigenpie Config Contract
/// @notice Handles Eigenpie configuration
contract EigenpieConfig is IEigenpieConfig, AccessControlUpgradeable {
    mapping(bytes32 contractKey => address contractAddress) public contractMap;

    mapping(address token => bool isSupported) public isSupportedAsset;
    mapping(address token => uint256 amount) public depositLimitByAsset;
    mapping(address token => address mLRTReceipt) public mLRTReceiptByAsset;
    mapping(address token => uint256 boost) public boostByAsset;
    mapping(address token => address strategy) public override assetStrategy;

    address[] public supportedAssetList;

    // 1st ugprade
    /// @dev A base tx gas amount for a transaction to be added for redemption later - in gas units
    uint256 public baseGasAmountSpent;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*/////////////////// ERROR /////////////////////*/
    error InvalidAsset();
    /*/////////////////// END /////////////////////*/

    modifier onlySupportedAsset(address asset) {
        if (!isSupportedAsset[asset]) {
            revert AssetNotSupported();
        }
        _;
    }

    /// @dev Initializes the contract
    /// @param admin Admin address
    function initialize(address admin) external initializer {
        UtilLib.checkNonZeroAddress(admin);

        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @dev Adds a new supported asset
    /// @param asset Asset address
    /// @param mLRTReceipt MLRT receipt
    /// @param depositLimit Deposit limit for the asset
    function addNewSupportedAsset(
        address asset,
        address mLRTReceipt,
        uint256 depositLimit
    )
        external
        onlyRole(EigenpieConstants.MANAGER)
    {
        _addNewSupportedAsset(asset, mLRTReceipt, depositLimit);
    }

    /// @dev Adds a new supported asset
    /// @param asset Asset address
    /// @param mLRTReceipt MLRT receipt
    function updateReceiptToken(
        address asset,
        address mLRTReceipt
    )
        external
        onlyRole(EigenpieConstants.DEFAULT_ADMIN_ROLE)
    {
        if (!isSupportedAsset[asset]) {
            revert AssetNotSupported();
        }

        if (asset != IMLRT(mLRTReceipt).underlyingAsset()) revert InvalidAsset();
        mLRTReceiptByAsset[asset] = mLRTReceipt;

        emit ReceiptTokenUpdated(asset, mLRTReceipt);
    }

    /// @dev private function to add a new supported asset
    /// @param asset Asset address
    /// @param depositLimit Deposit limit for the asset
    function _addNewSupportedAsset(address asset, address mLRTReceipt, uint256 depositLimit) private {
        UtilLib.checkNonZeroAddress(asset);
        UtilLib.checkNonZeroAddress(mLRTReceipt);

        if (isSupportedAsset[asset]) {
            revert AssetAlreadySupported();
        }

        if (asset != IMLRT(mLRTReceipt).underlyingAsset()) revert InvalidAsset();

        isSupportedAsset[asset] = true;
        mLRTReceiptByAsset[asset] = mLRTReceipt;

        supportedAssetList.push(asset);
        depositLimitByAsset[asset] = depositLimit;

        boostByAsset[asset] = EigenpieConstants.DENOMINATOR;

        emit AddedNewSupportedAsset(asset, mLRTReceipt, depositLimit);
    }

    /// @dev Updates the deposit limit for an asset
    /// @param asset Asset address
    /// @param depositLimit New deposit limit
    function updateAssetDepositLimit(
        address asset,
        uint256 depositLimit
    )
        external
        onlyRole(EigenpieConstants.MANAGER)
        onlySupportedAsset(asset)
    {
        depositLimitByAsset[asset] = depositLimit;
        emit AssetDepositLimitUpdate(asset, depositLimit);
    }

    /// @dev Updates the strategy for an asset
    /// @param asset Asset address
    /// @param strategy New strategy address
    function updateAssetStrategy(
        address asset,
        address strategy
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        onlySupportedAsset(asset)
    {
        UtilLib.checkNonZeroAddress(strategy);
        if (assetStrategy[asset] == strategy) {
            revert ValueAlreadyInUse();
        }

        if (asset != address(IStrategy(strategy).underlyingToken())) revert InvalidAsset();

        assetStrategy[asset] = strategy;
        emit AssetStrategyUpdate(asset, strategy);
    }

    /// @dev Updates the point boost for an asset
    /// @param asset Asset address
    /// @param boost point boost effect
    function updateAssetBoost(
        address asset,
        uint256 boost
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        onlySupportedAsset(asset)
    {
        boostByAsset[asset] = boost;

        emit AssetBoostUpdate(asset, boost);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

    function getContract(bytes32 contractKey) external view override returns (address) {
        return contractMap[contractKey];
    }

    function getSupportedAssetList() external view override returns (address[] memory) {
        return supportedAssetList;
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    function setContract(bytes32 contractKey, address contractAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(contractKey, contractAddress);
    }

    function setBaseGasAmountSpent(uint256 _baseGasAmountSpent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseGasAmountSpent = _baseGasAmountSpent;
    }

    /// @dev private function to set a contract
    /// @param key Contract key
    /// @param val Contract address
    function _setContract(bytes32 key, address val) private {
        UtilLib.checkNonZeroAddress(val);
        if (contractMap[key] == val) {
            revert ValueAlreadyInUse();
        }
        contractMap[key] = val;
        emit SetContract(key, val);
    }
}
