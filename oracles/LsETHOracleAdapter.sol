// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface ILsETH {
    function totalSupply() external view returns (uint256);
    function totalUnderlyingSupply() external view returns (uint256);
}

/// @title ETHxOracleAdapter Contract
/// @notice contract that fetches ETHx -> eth exchange rate
contract LsETHOracleAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    ILsETH public lsETH;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address lsETH_, address eigenpieConfig_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);
        UtilLib.checkNonZeroAddress(lsETH_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);
        lsETH = ILsETH(lsETH_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// @notice Fetches LST/ETH exchange rate
    /// @return assetPrice exchange rate of asset
    function getExchangeRateToNative() external view returns (uint256) {
        uint256 exchangeRate = (lsETH.totalUnderlyingSupply() * 1e18) / lsETH.totalSupply();
        return exchangeRate;
    }
}
