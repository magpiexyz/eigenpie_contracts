// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

interface IExchangeRateAdapter {
    function getExchangeRateToNative() external view returns (uint256);
}
