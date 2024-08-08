// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMLRT is IERC20 {
    function updateExchangeRateToLST(uint256 _newRate) external;

    function exchangeRateToLST() external view returns (uint256);

    function underlyingAsset() external view returns (address);

    function mint(address to, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}
