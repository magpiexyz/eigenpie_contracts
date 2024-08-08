// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

interface IPriceProvider {
    // errors
    error NewRateTooHigh();
    error NewRateTooLow();
    error UpdateTooFrequently();

    // events
    event AssetPriceAdapterUpdate(address indexed asset, address indexed priceOracle);
    event ExchangeRateUpdate(address indexed asset, address indexed receipt, uint256 newExchangeRate);
    event RateUpdateCeilingUpdate(address indexed caller, uint256 newRateLimit, uint256 newWindowLimit);
    event EigenpieEnterpriseSet(address indexed eigenpieEnterprise);

    // methods
    function getAssetPrice(address asset) external view returns (uint256);
    function assetPriceOracle(address asset) external view returns (address);
}
