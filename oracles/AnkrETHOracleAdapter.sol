// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IAnkrETHRateProvider {
    function getRate() external view returns (uint256);
}

/// @title AnkrETHOracleAdapter Contract
/// @notice contract that fetches ankrETH -> eth exchange rate
contract AnkrETHOracleAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    IAnkrETHRateProvider public ankrETHRateProvider;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address ankrETHRateProvider_, address eigenpieConfig_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);
        UtilLib.checkNonZeroAddress(ankrETHRateProvider_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);
        ankrETHRateProvider = IAnkrETHRateProvider(ankrETHRateProvider_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// @notice Fetches LST/ETH exchange rate
    /// @return assetPrice exchange rate of asset
    function getExchangeRateToNative() external view returns (uint256) {
        return ankrETHRateProvider.getRate();
    }
}
