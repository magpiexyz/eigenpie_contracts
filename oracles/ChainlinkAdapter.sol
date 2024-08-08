// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";

import { IExchangeRateAdapter } from "../interfaces/IExchangeRateAdapter.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IAggregatorV3Interface {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title ChainlinkPriceOracle Contract
/// @notice contract that fetches the exchange rate of assets from chainlink price feeds
contract ChainlinkAdapter is IExchangeRateAdapter, EigenpieConfigRoleChecker, Initializable {
    IAggregatorV3Interface public priceFeed;

    event PriceFeedUpdate(address priceFeed);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param eigenpieConfig_ eigenpie config address
    function initialize(address eigenpieConfig_, address priceFeed_) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfig_);
        UtilLib.checkNonZeroAddress(priceFeed_);

        eigenpieConfig = IEigenpieConfig(eigenpieConfig_);
        priceFeed = IAggregatorV3Interface(priceFeed_);

        emit UpdatedEigenpieConfig(address(eigenpieConfig));
    }

    /// @notice Fetches LST/ETH exchange rate
    /// @return assetPrice exchange rate of asset
    function getExchangeRateToNative() external view returns (uint256) {
        (, int256 price,,,) = IAggregatorV3Interface(priceFeed).latestRoundData();

        return uint256(price) * 1e18 / 10 ** uint256(IAggregatorV3Interface(priceFeed).decimals());
    }

    /// @dev add/update the price oracle of any supported asset
    /// @dev only Oracle Admin is allowed
    /// @param newPriceFeed chainlink price feed contract which contains exchange rate info
    function updatePriceFeedFor(address newPriceFeed) external onlyOracleAdmin {
        UtilLib.checkNonZeroAddress(newPriceFeed);

        priceFeed = IAggregatorV3Interface(newPriceFeed);

        emit PriceFeedUpdate(address(priceFeed));
    }
}
