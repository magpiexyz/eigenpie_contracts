// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

interface IRateProvider {
    function getRate() external view returns (uint256);
}
