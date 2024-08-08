// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../interfaces/IRateProvider.sol";
import "../interfaces/IMLRT.sol";

/**
 * @title MSW Rate Provider
 * @notice Returns the rate of 1 mswETH in terms of swETH
 */
contract MswETHRateProvider is IRateProvider {
    address public immutable mswETH;

    constructor(address _mswETH) {
        mswETH = _mswETH;
    }

    /**
     * @return uint256  the rate of 1 mswETH in terms of swETH
     */
    function getRate() external view override returns (uint256) {
        return IMLRT(mswETH).exchangeRateToLST();
    }
}
