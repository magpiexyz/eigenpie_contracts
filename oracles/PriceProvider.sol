// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";
import { TransferHelper } from "../utils/TransferHelper.sol";
import { EigenpieConstants } from "../utils/EigenpieConstants.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";
import { IEigenpieEnterprise } from "../interfaces/IEigenpieEnterprise.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { IPriceProvider } from "../interfaces/IPriceProvider.sol";
import { IMLRT } from "../interfaces/IMLRT.sol";
import { IEigenpieStaking } from "../interfaces/IEigenpieStaking.sol";
import { INodeDelegator } from "../interfaces/INodeDelegator.sol";
import { IDelayedWithdrawalRouter } from "../interfaces/eigenlayer/IDelayedWithdrawalRouter.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title PriceProvider Contract
/// @notice contract that calculates the exchange rate of assets

contract PriceProvider is IPriceProvider, EigenpieConfigRoleChecker, Initializable {
    uint256 public rateIncreaseLimit; // as a protection
    uint256 public rateChangeWindowLimit; // as a protection

    mapping(address asset => address priceOracle) public override assetPriceOracle;
    mapping(address receipt => uint256 timestamp) public rateLastUpdate;

    IEigenpieEnterprise public eigenpieEnterprise;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfigAddr eigenpie config address
    function initialize(address eigenpieConfigAddr) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfigAddr);

        eigenpieConfig = IEigenpieConfig(eigenpieConfigAddr);

        rateIncreaseLimit = 100; // can't have +- more than 1%
        rateChangeWindowLimit = 2 hours;
    }

    /*//////////////////////////////////////////////////////////////
                            view functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Provides LST/ETH exchange rate
    /// @dev reads from ExchangeRate Adapter interface which may fetch price from any supported oracle
    /// @param asset the LST for which exchange rate is required
    /// @return exchangeRate exchange rate of asset
    function getAssetPrice(address asset) public view onlySupportedAsset(asset) returns (uint256) {
        return IExchangeRateAdapter(assetPriceOracle[asset]).getExchangeRateToNative();
    }

    function batchUpdateMLRTPrice(address[] memory assets) external onlyOracle {
        for (uint256 i=0; i<assets.length; i++){
            uint256 exchangeRate = _calculateExchangeRate(assets[i]);
            _checkNewRate(assets[i], exchangeRate);

            _updateMLRTPrice(assets[i], exchangeRate);
        }
    }

    // /// @notice updates mLRT-LST/LST exchange rate
    // /// @dev calculates based on stakedAsset value received from eigen layer
    // /// @param asset the asset for which exchange rate to update
    function updateMLRTPrice(address asset) external onlyOracle {
        uint256 exchangeRate = _calculateExchangeRate(asset);        
        _checkNewRate(asset, exchangeRate);
        
        _updateMLRTPrice(asset, exchangeRate);
    }

    /// @notice updates mLRT-LST/LST exchange rate manually for gas fee saving
    /// @dev calculates based on stakedAsset value received from eigen layer
    /// @param asset the asset for which exchange rate to update
    /// @param newExchangeRate the new exchange rate to update
    function updateMLRTPrice(address asset, uint256 newExchangeRate) external onlyOracleAdmin {
        _checkNewRate(asset, newExchangeRate);

        _updateMLRTPrice(asset, newExchangeRate);
    }

    function claimAndUpdateNativeMLRTPrice(address nodeDelagator) external onlyOracle {
        uint256 maxNumber = type(uint256).max;
        IDelayedWithdrawalRouter(eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_DWR)).claimDelayedWithdrawals(nodeDelagator, maxNumber);
        
        address asset = EigenpieConstants.PLATFORM_TOKEN_ADDRESS; // egETH
        uint256 exchangeRate = _calculateExchangeRate(asset);
        _checkNewRate(asset, exchangeRate);

        _updateMLRTPrice(asset, exchangeRate);
    }

    /*//////////////////////////////////////////////////////////////
                            write functions
    //////////////////////////////////////////////////////////////*/

    /// @dev add/update the price oracle of any supported asset
    /// @dev only LRTManager is allowed
    /// @param asset asset address for which oracle price needs to be added/updated
    function updatePriceAdapterFor(
        address asset,
        address priceAdapter
    )
        external
        onlyOracleAdmin
        onlySupportedAsset(asset)
    {
        UtilLib.checkNonZeroAddress(priceAdapter);
        assetPriceOracle[asset] = priceAdapter;

        emit AssetPriceAdapterUpdate(asset, priceAdapter);
    }

    function updateExchangeRateCeiling(uint256 newCeiling, uint256 newWindowLimit) external onlyDefaultAdmin {
        rateIncreaseLimit = newCeiling;
        rateChangeWindowLimit = newWindowLimit;

        emit RateUpdateCeilingUpdate(msg.sender, rateIncreaseLimit, rateChangeWindowLimit);
    }

    function setEigenpieEnterprise(address newEigenpieEnterprise) external onlyDefaultAdmin {
        UtilLib.checkNonZeroAddress(newEigenpieEnterprise);
        eigenpieEnterprise = IEigenpieEnterprise(newEigenpieEnterprise);

        emit EigenpieEnterpriseSet(newEigenpieEnterprise);
    }


    /*//////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    function _checkNewRate(address asset, uint256 newRate) internal {
        address mLRTReceipt = eigenpieConfig.mLRTReceiptByAsset(asset);

        if (block.timestamp - rateLastUpdate[mLRTReceipt] < rateChangeWindowLimit) revert UpdateTooFrequently();

        uint256 currentExchangeRate = IMLRT(mLRTReceipt).exchangeRateToLST();

        if (
            newRate * EigenpieConstants.DENOMINATOR
                > currentExchangeRate * (EigenpieConstants.DENOMINATOR + rateIncreaseLimit)
        ) {
            revert NewRateTooHigh();
        }

        if (
            newRate * EigenpieConstants.DENOMINATOR
                < currentExchangeRate * (EigenpieConstants.DENOMINATOR - rateIncreaseLimit)
        ) {
            revert NewRateTooLow();
        }

        rateLastUpdate[mLRTReceipt] = block.timestamp;
    }

    function _updateMLRTPrice(address asset, uint256 exchangeRate) internal {
        address mLRTReceipt = eigenpieConfig.mLRTReceiptByAsset(asset);

        IMLRT(mLRTReceipt).updateExchangeRateToLST(exchangeRate);
        emit ExchangeRateUpdate(asset, mLRTReceipt, exchangeRate);
    }

    function _calculateExchangeRate(address asset) internal returns (uint256 exchangeRate) {
        address mLRTReceipt = eigenpieConfig.mLRTReceiptByAsset(asset);
        uint256 receiptSupply = IMLRT(mLRTReceipt).totalSupply();
        uint256 enterpriseMlrtMinted = eigenpieEnterprise.totalMintedMlrt(mLRTReceipt);

        if (receiptSupply - enterpriseMlrtMinted == 0) {
            exchangeRate = 1 ether;
        } else {
            address eigenStakingAddr = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_STAKING);
            uint256 totalLST = IEigenpieStaking(eigenStakingAddr).getTotalAssetDeposits(asset);
            exchangeRate = totalLST * 1 ether / (receiptSupply - enterpriseMlrtMinted);
        }
    }
}