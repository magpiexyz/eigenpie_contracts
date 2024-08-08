// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../interfaces/IRateProvider.sol";
import "../interfaces/IMLRT.sol";
/**
 * @title MST Rate Provider
 * @notice Returns the rate of 1 mstETH in terms of stETH
 */

contract MstETHRateProvider is IRateProvider {
    address public immutable mstETH;

    constructor(address _mstETH) {
        mstETH = _mstETH;
    }

    /**
     * @return uint256  the rate of 1 mstETH in terms of stETH
     */
    function getRate() external view override returns (uint256) {
        return IMLRT(mstETH).exchangeRateToLST();
    }
}
