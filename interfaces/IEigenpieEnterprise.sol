// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

interface IEigenpieEnterprise {
    // Sturcts
    struct ClientData {
        bool registered;
        uint256 nativeRestakedAmount;
        uint256 nativeUsed;
        uint256 mlrtMinted;
        uint256 exchangeRate; // client's own exchange rate of mLRT to native
        address mlrtWallet;
        address eigenPod;
    }

    struct LSTData {
        uint256 lstRestakedAmount;
        uint256 lstUsed;
        uint256 exchangeRate;
        uint256 mlrtMinted;
    }

    // Errors
    error InvalidClient();
    error AssetNotEnough(uint256 quotaLeft, uint256 toUse);
    error InvalidMLRTAsset();
    error EnoughCollateral();
    error BurnTooMuch();
    error EigenPodAlreadySet();
    error EigenpodMisMatch();

    // Events
    event UpdateAllowedClient(address indexed client, address eigenPod);
    event UpdateClientLSTRestakedAmount(address indexed client, address underlyingToken, uint256 lstRestakedAmount);
    event UpdateClientNativeRestakedAmount(address indexed client, uint256 nativeRestakedAmount);
    event ClientRegisterRestake(
        address indexed client,
        address indexed mlrtWallet,
        address underlyingToken,
        uint256 amountUsed,
        uint256 mlrtMinted
    );
    event BurnMLRTFromWallet(address indexed client, address asset, uint256 assetLess, uint256 mlrtBurnt);
    event EigenPodSet(address indexed client, address indexed eigenPod);

    // methods
    function getClientData(address client) external returns (ClientData memory clientData);
    function restakedLess(
        address client,
        address underlyingToken
    )
        external
        returns (uint256 lessAmount, uint256 mlrtShouldBurn);
    function getTotalMintedNativeMlrt() external returns (uint256 totalMlrt);
    function burnMLRT(address cleint, address mlrt, uint256 amount) external;
    function getClientAssetData(address client, address underlyingToken) external returns (LSTData memory lstData);
    function totalMintedMlrt(address asset) external returns (uint256 totalMlrtMinted);
    function syncClientRestakedAmount(address client) external;
}
