// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

interface IMLRTWallet {
    // Errors
    error OnlyClient();
    error NotAllowedCaller();
    error PublicWithdrawTooMuch();

    // Events
    event UpdateAllowedClient(address indexed client, bool allowed);
    event DepositToZicruit(address indexed caller, address mlrt, uint256 amount);
    event DepositToSwellStaking(address indexed caller, address mlrt, uint256 amount);
    event WithdrawFromZicruit(address indexed caller, address mlrt, uint256 amount);
    event WithdrawFromSwellStaking(address indexed caller, address mlrt, uint256 amount);
    event AllowedClientOperatorUpdated(address indexed client, bool allowed);
    event EigenPodUpdated(address indexed client, address indexed eigenPod);

    // methods
    function initialize(
        address client,
        address eigenPod,
        address eigenpieConfig,
        address engienpieEnterprise
    )
        external;
    function restakedLess(address underlyingToken) external returns (uint256 ethLess, uint256 shouldBurn);
    function setEigenPod(address eigenPod) external;
    function eigenPod() external view returns (address);
}
