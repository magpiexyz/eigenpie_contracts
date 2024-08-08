// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IDIATwoAssetAdapter {
    function getAPriceInB() external view returns (uint256, uint256, uint256);
}

/// @title OETHOracleAdapter Contract
/// @notice contract that fetches oETH -> eth exchange rate
contract OETHOracleAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    IDIATwoAssetAdapter public diaTwoAssetAdapter;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address diaTwoAssetAdapter_, address eigenpieConfig_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);
        UtilLib.checkNonZeroAddress(diaTwoAssetAdapter_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);
        diaTwoAssetAdapter = IDIATwoAssetAdapter(diaTwoAssetAdapter_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// @notice Fetches LST/ETH exchange rate
    /// @return assetPrice exchange rate of asset
    function getExchangeRateToNative() external view returns (uint256) {
        (uint256 _exchangeRate,,) = diaTwoAssetAdapter.getAPriceInB();
        return _exchangeRate * 1e10;
    }
}
