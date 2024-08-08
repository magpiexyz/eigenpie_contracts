// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IStaderStakePoolsManager {
    function getExchangeRate() external view returns (uint256);
}

/// @title ETHxOracleAdapter Contract
/// @notice contract that fetches ETHx -> eth exchange rate
contract ETHxOracleAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    IStaderStakePoolsManager public staderStakePoolsManager;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address staderStakePoolsManager_, address eigenpieConfig_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);
        UtilLib.checkNonZeroAddress(staderStakePoolsManager_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);
        staderStakePoolsManager = IStaderStakePoolsManager(staderStakePoolsManager_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// @notice Fetches LST/ETH exchange rate
    /// @return assetPrice exchange rate of asset
    function getExchangeRateToNative() external view returns (uint256) {
        return staderStakePoolsManager.getExchangeRate();
    }
}
