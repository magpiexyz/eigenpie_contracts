// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title ConstantOracleAdapter Contract
/// An oracle adapter always return 1 : 1 constant
contract ConstantOracleAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address eigenpieConfig_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// Native Eth to Native eth rate is constant
    function getExchangeRateToNative() external pure returns (uint256) {
        return 1e18;
    }
}
