// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

interface IEigenpiePreDepositHelper {
    function feedUserDeposit(address user, address asset, uint256 mintedAmount) external;
    function withdraw(uint256 _cycle, address _user, address _asset, address _receipt, uint256 _mlrtAmount) external;

    function claimableCycles(uint256 cycle) external returns (bool isClaimmable);
}
