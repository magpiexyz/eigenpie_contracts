// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";
import { IMLRT } from "../interfaces/IMLRT.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EigenpieConstants } from "../utils/EigenpieConstants.sol";

/// @title RemotePriceProvider Contract
/// @notice contract that modifies exchange rate of remote MLRTs
contract RemotePriceProvider is EigenpieConfigRoleChecker, Initializable {
    uint256 public rateIncreaseLimit; // as a protection
    uint256 public rateChangeWindowLimit; // as a protection

    mapping(address mlrt => uint256 timestamp) public rateLastUpdate;

    // events
    event ExchangeRateUpdate(address mlrt, uint256 exchangeRate);
    event RateUpdateCeilingUpdate(address indexed caller, uint256 newRateLimit, uint256 newWindowLimit);

    // errors
    error NewRateTooHigh();
    error NewRateTooLow();
    error UpdateTooFrequently();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address eigenpieConfigAddr) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfigAddr);

        eigenpieConfig = IEigenpieConfig(eigenpieConfigAddr);

        rateIncreaseLimit = 100; // can't have +- more than 1%
        rateChangeWindowLimit = 2 hours;
    }

    /// @notice updates mLRT-LST/LST exchange rate manually
    /// @param mlrt the mlrt for which exchange rate to update
    /// @param newExchangeRate the new exchange rate to update
    function updateMLRTPrice(address mlrt, uint256 newExchangeRate) external onlyOracle {
        _checkNewRate(mlrt, newExchangeRate);

        IMLRT(mlrt).updateExchangeRateToLST(newExchangeRate);
        rateLastUpdate[mlrt] = block.timestamp;

        emit ExchangeRateUpdate(mlrt, newExchangeRate);
    }

    function _checkNewRate(address mlrt, uint256 newRate) internal {
        if (block.timestamp - rateLastUpdate[mlrt] < rateChangeWindowLimit) revert UpdateTooFrequently();

        uint256 currentExchangeRate = IMLRT(mlrt).exchangeRateToLST();

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

        rateLastUpdate[mlrt] = block.timestamp;
    }

    function updateExchangeRateCeiling(uint256 newCeiling, uint256 newWindowLimit) external onlyDefaultAdmin {
        rateIncreaseLimit = newCeiling;
        rateChangeWindowLimit = newWindowLimit;

        emit RateUpdateCeilingUpdate(msg.sender, rateIncreaseLimit, rateChangeWindowLimit);
    }
}
