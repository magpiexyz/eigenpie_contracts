// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface ICbETH {
    function exchangeRate() external view returns (uint256);
}

/// @title cbETHOracleAdapter Contract
/// @notice contract that fetches cbETH -> eth exchange rate
contract CbETHOracleAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    ICbETH public cbETH;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address cbETH_, address eigenpieConfig_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);
        UtilLib.checkNonZeroAddress(cbETH_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);
        cbETH = ICbETH(cbETH_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// @notice Fetches LST/ETH exchange rate
    /// @return assetPrice exchange rate of asset
    function getExchangeRateToNative() external view returns (uint256) {
        return cbETH.exchangeRate();
    }
}
