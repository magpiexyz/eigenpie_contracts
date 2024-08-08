// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IMantleEthStaking {
    function mETHToETH(uint256 mETHAmount) external view returns (uint256);
}

/// @title SfrxETHOracleAdapter Contract
/// @notice contract that fetches sfrxETH -> eth exchange rate
contract MethOracleAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    IMantleEthStaking public mantleEthstaking;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address mantleEthstaking_, address eigenpieConfig_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);
        UtilLib.checkNonZeroAddress(mantleEthstaking_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);
        mantleEthstaking = IMantleEthStaking(mantleEthstaking_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// @notice Fetches LST/ETH exchange rate
    /// @return assetPrice exchange rate of asset
    function getExchangeRateToNative() external view returns (uint256) {
        return mantleEthstaking.mETHToETH(1 ether);
    }
}
