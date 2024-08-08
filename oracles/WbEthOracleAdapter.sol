// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IWBETH {
    function exchangeRate() external view returns (uint256 _exchangeRate);
}

/// @title WbEthOracleAdapter Contract
/// @notice contract that fetches WBETH -> eth exchange rate
contract WbEthOracleAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    IWBETH public wBETH;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address wBETH_, address eigenpieConfig_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);
        UtilLib.checkNonZeroAddress(wBETH_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);
        wBETH = IWBETH(wBETH_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// @notice Fetches LST/ETH exchange rate
    /// @return assetPrice exchange rate of asset
    function getExchangeRateToNative() external view returns (uint256) {
        return wBETH.exchangeRate();
    }
}
