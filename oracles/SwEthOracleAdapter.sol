// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface ISwETH {
    function swETHToETHRate() external view returns (uint256);
}

/// @title SwEthOracleAdapter Contract
/// @notice contract that fetches swETH -> eth exchange rate
contract SwEthOracleAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    ISwETH public swETH;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address swETH_, address eigenpieConfig_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);
        UtilLib.checkNonZeroAddress(swETH_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);
        swETH = ISwETH(swETH_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// @notice Fetches LST/ETH exchange rate
    /// @return assetPrice exchange rate of asset
    function getExchangeRateToNative() external view returns (uint256) {
        return swETH.swETHToETHRate();
    }
}
