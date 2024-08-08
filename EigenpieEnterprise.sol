// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "./utils/UtilLib.sol";
import { EigenpieConstants } from "./utils/EigenpieConstants.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "./utils/EigenpieConfigRoleChecker.sol";
import { IEigenpieEnterprise } from "./interfaces/IEigenpieEnterprise.sol";
import { IMLRTWallet } from "./interfaces/IMLRTWallet.sol";
import { IMLRT } from "./interfaces/IMLRT.sol";
import { IEigenPod } from "./interfaces/eigenlayer/IEigenPod.sol";
import { IEigenPodManager } from "./interfaces/IEigenPodManager.sol";
import { IStrategy } from "./interfaces/eigenlayer/IStrategy.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

contract EigenpieEnterprise is
    IEigenpieEnterprise,
    EigenpieConfigRoleChecker,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    mapping(address => ClientData) public allowedClients;
    mapping(address => bool) public registeredPod;
    // keep tracking of total enterprise minted mRLT by receipt
    mapping(address => uint256) public totalMintedMlrt;

    address[] public allClients;

    // mLRT Wallet upgradable beacon
    address public mLRTWalletBeacon;

    bytes internal constant BeaconProxyBytecode =
        hex"608060405260405161090e38038061090e83398101604081905261002291610460565b61002e82826000610035565b505061058a565b61003e83610100565b6040516001600160a01b038416907f1cf3b03a6cf19fa2baba4df148e9dcabedea7f8a5c07840e207e5c089be95d3e90600090a260008251118061007f5750805b156100fb576100f9836001600160a01b0316635c60da1b6040518163ffffffff1660e01b8152600401602060405180830381865afa1580156100c5573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906100e99190610520565b836102a360201b6100291760201c565b505b505050565b610113816102cf60201b6100551760201c565b6101725760405162461bcd60e51b815260206004820152602560248201527f455243313936373a206e657720626561636f6e206973206e6f74206120636f6e6044820152641d1c9858dd60da1b60648201526084015b60405180910390fd5b6101e6816001600160a01b0316635c60da1b6040518163ffffffff1660e01b8152600401602060405180830381865afa1580156101b3573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101d79190610520565b6102cf60201b6100551760201c565b61024b5760405162461bcd60e51b815260206004820152603060248201527f455243313936373a20626561636f6e20696d706c656d656e746174696f6e206960448201526f1cc81b9bdd08184818dbdb9d1c9858dd60821b6064820152608401610169565b806102827fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d5060001b6102de60201b6100641760201c565b80546001600160a01b0319166001600160a01b039290921691909117905550565b60606102c883836040518060600160405280602781526020016108e7602791396102e1565b9392505050565b6001600160a01b03163b151590565b90565b6060600080856001600160a01b0316856040516102fe919061053b565b600060405180830381855af49150503d8060008114610339576040519150601f19603f3d011682016040523d82523d6000602084013e61033e565b606091505b5090925090506103508683838761035a565b9695505050505050565b606083156103c65782516103bf576001600160a01b0385163b6103bf5760405162461bcd60e51b815260206004820152601d60248201527f416464726573733a2063616c6c20746f206e6f6e2d636f6e74726163740000006044820152606401610169565b50816103d0565b6103d083836103d8565b949350505050565b8151156103e85781518083602001fd5b8060405162461bcd60e51b81526004016101699190610557565b80516001600160a01b038116811461041957600080fd5b919050565b634e487b7160e01b600052604160045260246000fd5b60005b8381101561044f578181015183820152602001610437565b838111156100f95750506000910152565b6000806040838503121561047357600080fd5b61047c83610402565b60208401519092506001600160401b038082111561049957600080fd5b818501915085601f8301126104ad57600080fd5b8151818111156104bf576104bf61041e565b604051601f8201601f19908116603f011681019083821181831017156104e7576104e761041e565b8160405282815288602084870101111561050057600080fd5b610511836020830160208801610434565b80955050505050509250929050565b60006020828403121561053257600080fd5b6102c882610402565b6000825161054d818460208701610434565b9190910192915050565b6020815260008251806020840152610576816040850160208701610434565b601f01601f19169190910160400192915050565b61034e806105996000396000f3fe60806040523661001357610011610017565b005b6100115b610027610022610067565b610100565b565b606061004e83836040518060600160405280602781526020016102f260279139610124565b9392505050565b6001600160a01b03163b151590565b90565b600061009a7fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50546001600160a01b031690565b6001600160a01b0316635c60da1b6040518163ffffffff1660e01b8152600401602060405180830381865afa1580156100d7573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906100fb9190610249565b905090565b3660008037600080366000845af43d6000803e80801561011f573d6000f35b3d6000fd5b6060600080856001600160a01b03168560405161014191906102a2565b600060405180830381855af49150503d806000811461017c576040519150601f19603f3d011682016040523d82523d6000602084013e610181565b606091505b50915091506101928683838761019c565b9695505050505050565b6060831561020d578251610206576001600160a01b0385163b6102065760405162461bcd60e51b815260206004820152601d60248201527f416464726573733a2063616c6c20746f206e6f6e2d636f6e747261637400000060448201526064015b60405180910390fd5b5081610217565b610217838361021f565b949350505050565b81511561022f5781518083602001fd5b8060405162461bcd60e51b81526004016101fd91906102be565b60006020828403121561025b57600080fd5b81516001600160a01b038116811461004e57600080fd5b60005b8381101561028d578181015183820152602001610275565b8381111561029c576000848401525b50505050565b600082516102b4818460208701610272565b9190910192915050565b60208152600082518060208401526102dd816040850160208701610272565b601f01601f1916919091016040019291505056fe416464726573733a206c6f772d6c6576656c2064656c65676174652063616c6c206661696c6564a2646970667358221220d51e81d3bc5ed20a26aeb05dce7e825c503b2061aa78628027300c8d65b9d89a64736f6c634300080c0033416464726573733a206c6f772d6c6576656c2064656c65676174652063616c6c206661696c6564";

    mapping(address => mapping(address => LSTData)) public clientAssetMapping;
    uint256[50] private __gap; // reserve for upgrade

    constructor() {
        _disableInitializers();
    }

    function initialize(address _eigenpieConfigAddr, address _mLRTWalletBeacon) external initializer {
        UtilLib.checkNonZeroAddress(_eigenpieConfigAddr);

        __Pausable_init();
        __ReentrancyGuard_init();

        eigenpieConfig = IEigenpieConfig(_eigenpieConfigAddr);
        mLRTWalletBeacon = _mLRTWalletBeacon;

        emit UpdatedEigenpieConfig(_eigenpieConfigAddr);
    }

    modifier onlyAllowedClient() {
        ClientData memory clientData = allowedClients[msg.sender];

        if (clientData.registered != true) revert InvalidClient();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    function getClient(uint256 index) external view returns (address) {
        return allClients[index];
    }

    function getClientLength() external view returns (uint256) {
        return allClients.length;
    }

    function getClientData(address client) external view override returns (ClientData memory clientData) {
        clientData = allowedClients[client];
    }

    function getClientAssetData(
        address client,
        address underlyingToken
    )
        external
        view
        returns (LSTData memory lstData)
    {
        return clientAssetMapping[client][underlyingToken];
    }

    function getTotalMintedNativeMlrt() external view override returns (uint256 totalMlrt) {
        address receipt = eigenpieConfig.mLRTReceiptByAsset(EigenpieConstants.PLATFORM_TOKEN_ADDRESS);

        return totalMintedMlrt[receipt];
    }

    function restakedLess(
        address client,
        address underlyingToken
    )
        external
        view
        override
        returns (uint256 underlyingLessAmount, uint256 mlrtShouldBurn)
    {
        return _checkCollateralLess(client, underlyingToken);
    }

    function getRestakingShares(address client) public view returns (address[] memory, uint256[] memory) {
        uint256 podShares = _getPodShares(client);
        (address[] memory underlyingTokens, uint256[] memory underlyingAmounts, uint256 assetLength) =
            _getStrategyShares(client); // The last entry here will be vacant reason being native strategy is not included
            // in the strategies array

        // Add native strategy (platform token) shares to the array
        underlyingTokens[assetLength - 1] = EigenpieConstants.PLATFORM_TOKEN_ADDRESS;
        underlyingAmounts[assetLength - 1] = podShares;
        return (underlyingTokens, underlyingAmounts);
    }

    /*//////////////////////////////////////////////////////////////
                            Write functions
    //////////////////////////////////////////////////////////////*/

    function burnMLRT(address client, address mlrtAsset, uint256 amountToBurn) external nonReentrant {
        address asset = IMLRT(mlrtAsset).underlyingAsset();
        if (mlrtAsset != eigenpieConfig.mLRTReceiptByAsset(asset)) revert InvalidMLRTAsset();

        ClientData storage clientData = allowedClients[client];
        if (!clientData.registered) revert InvalidClient();

        if (msg.sender != clientData.mlrtWallet) {
            // Update the client restaking data only if the caller is not mLRTWallet. This prevents a double update, as
            // mLRTWallet already updates the data before calling this function
            _updateClientRestakingData(client, clientData);
        }

        (uint256 valuedAssetLess, uint256 shouldBurn) = _checkCollateralLess(client, asset);

        if (valuedAssetLess == 0) revert EnoughCollateral();
        if (amountToBurn > shouldBurn) revert BurnTooMuch();

        valuedAssetLess = valuedAssetLess * amountToBurn / shouldBurn;

        _burnFromWallet(client, asset, valuedAssetLess, amountToBurn);

        emit BurnMLRTFromWallet(client, asset, valuedAssetLess, amountToBurn);
    }

    /*//////////////////////////////////////////////////////////////
                            Client functions
    //////////////////////////////////////////////////////////////*/

    function registerReStaking(
        address underlyingToken,
        uint256 amountToMintMlt
    )
        external
        nonReentrant
        onlyAllowedClient
    {
        ClientData storage clientData = allowedClients[msg.sender];
        address receipt;
        uint256 amountToMint;
        _updateClientRestakingData(msg.sender, clientData);
        _checkValidMint(msg.sender, clientData, underlyingToken, amountToMintMlt);
        (receipt, amountToMint) = _calculateMintAndUpdate(msg.sender, underlyingToken, amountToMintMlt);

        if (clientData.mlrtWallet == address(0)) {
            clientData.mlrtWallet = _deployMLRTWallet(msg.sender, clientData.eigenPod);
        }

        IMLRT(receipt).mint(clientData.mlrtWallet, amountToMint);
        totalMintedMlrt[receipt] += amountToMint;

        emit ClientRegisterRestake(msg.sender, clientData.mlrtWallet, underlyingToken, amountToMintMlt, amountToMint);
    }

    // /*//////////////////////////////////////////////////////////////
    //                     Eigenpie Admin functions
    // //////////////////////////////////////////////////////////////*/

    function updateAllowedClient(address client) external onlyDefaultAdmin {
        ClientData storage clientData = allowedClients[client];

        if (!clientData.registered) {
            clientData.registered = true;
            allClients.push(client);
        }

        address eigenPod = _setEigenPod(client, clientData);
        _updateClientRestakingData(client, clientData);

        emit UpdateAllowedClient(client, eigenPod);
    }

    function syncClientRestakedAmount(address client) external nonReentrant {
        ClientData storage clientData = allowedClients[client];
        if (!clientData.registered) revert InvalidClient();
        _updateClientRestakingData(client, clientData);
    }

    function setEigenPod(address client) external {
        ClientData storage clientData = allowedClients[client];
        UtilLib.checkNonZeroAddress(clientData.mlrtWallet);

        _setEigenPod(client, clientData);
    }

    /*//////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    function _checkValidMint(
        address client,
        ClientData storage clientData,
        address underlyingToken,
        uint256 amountToMintMlt
    )
        internal
        view
    {
        uint256 quotaLeft;
        if (underlyingToken != EigenpieConstants.PLATFORM_TOKEN_ADDRESS) {
            LSTData memory lstData = clientAssetMapping[client][underlyingToken];
            quotaLeft = lstData.lstRestakedAmount - lstData.lstUsed;
        } else {
            quotaLeft = clientData.nativeRestakedAmount - clientData.nativeUsed;
        }
        if (quotaLeft < amountToMintMlt) {
            revert AssetNotEnough(quotaLeft, amountToMintMlt);
        }
    }

    function _deployMLRTWallet(address client, address eigenPod) internal returns (address) {
        // create the pod
        IMLRTWallet wallet = IMLRTWallet(
            Create2.deploy(
                0,
                bytes32(uint256(uint160(msg.sender))),
                // set the beacon address to the mLRTWalletBeacon and initialize it
                abi.encodePacked(BeaconProxyBytecode, abi.encode(mLRTWalletBeacon, ""))
            )
        );
        wallet.initialize(client, eigenPod, address(eigenpieConfig), address(this));
        // store the pod in the mapping
        return address(wallet);
    }

    function _calculateMintAndUpdate(
        address client,
        address asset,
        uint256 amountToMintMlt
    )
        internal
        returns (address receipt, uint256 mLRTAmountToMint)
    {
        receipt = eigenpieConfig.mLRTReceiptByAsset(asset);
        uint256 rate = IMLRT(receipt).exchangeRateToLST();
        mLRTAmountToMint = (amountToMintMlt * 1 ether) / rate;

        if (asset == EigenpieConstants.PLATFORM_TOKEN_ADDRESS) {
            //For native token, there is a special use case - EigenLayer only provides share info for native restaking,
            // so directly used shares instead of the underlying amount
            ClientData storage clientData = allowedClients[client];
            clientData.nativeUsed += amountToMintMlt;
            clientData.mlrtMinted += mLRTAmountToMint;
            clientData.exchangeRate = clientData.nativeUsed * 1 ether / clientData.mlrtMinted;
        } else {
            LSTData storage lstData = clientAssetMapping[client][asset];
            lstData.lstUsed += amountToMintMlt;
            lstData.mlrtMinted += mLRTAmountToMint;
            lstData.exchangeRate = lstData.lstUsed * 1 ether / lstData.mlrtMinted;
        }

        return (receipt, mLRTAmountToMint);
    }

    function _burnFromWallet(address client, address asset, uint256 lessAmount, uint256 shouldBurn) internal {
        address receipt = eigenpieConfig.mLRTReceiptByAsset(asset);
        ClientData storage clientData = allowedClients[client];
        IMLRT(receipt).burnFrom(clientData.mlrtWallet, shouldBurn);

        if (asset == EigenpieConstants.PLATFORM_TOKEN_ADDRESS) {
            if (clientData.mlrtMinted > shouldBurn) {
                clientData.mlrtMinted -= shouldBurn;
            } else {
                clientData.mlrtMinted = 0;
            }

            if (clientData.nativeUsed > lessAmount) {
                clientData.nativeUsed -= lessAmount;
            } else {
                clientData.nativeUsed = 0;
            }
        } else {
            LSTData storage lstData = clientAssetMapping[client][asset];

            if (lstData.mlrtMinted > shouldBurn) {
                lstData.mlrtMinted -= shouldBurn;
            } else {
                lstData.mlrtMinted = 0;
            }

            if (lstData.lstUsed > lessAmount) {
                lstData.lstUsed -= lessAmount;
            } else {
                lstData.lstUsed = 0;
            }
        }

        if (totalMintedMlrt[receipt] > shouldBurn) {
            totalMintedMlrt[receipt] -= shouldBurn;
        } else {
            totalMintedMlrt[receipt] = 0;
        }
    }

    function _checkCollateralLess(
        address client,
        address underlyingToken
    )
        internal
        view
        returns (uint256 collateralLess, uint256 shouldBurn)
    {
        uint256 valuedToken;
        uint256 restakedAmount;
        uint256 exchangeRate;

        if (underlyingToken == EigenpieConstants.PLATFORM_TOKEN_ADDRESS) {
            ClientData memory clientData = allowedClients[client];
            valuedToken = clientData.mlrtMinted * clientData.exchangeRate / 1 ether;
            restakedAmount = clientData.nativeRestakedAmount;
            exchangeRate = clientData.exchangeRate;
        } else {
            LSTData memory lstData = clientAssetMapping[client][underlyingToken];
            valuedToken = lstData.mlrtMinted * lstData.exchangeRate / 1 ether;
            restakedAmount = lstData.lstRestakedAmount;
            exchangeRate = lstData.exchangeRate;
        }

        if (valuedToken <= restakedAmount) {
            return (0, 0);
        }

        collateralLess = valuedToken - restakedAmount;
        shouldBurn = collateralLess * 1 ether / exchangeRate;
        return (collateralLess, shouldBurn);
    }

    function _updateClientRestakingData(address client, ClientData storage clientData) internal {
        (address[] memory underlyingTokens, uint256[] memory underlyingAmounts) = getRestakingShares(client);

        uint256 totalStrategies = underlyingTokens.length;
        for (uint256 i = 0; i < totalStrategies - 1; i++) {
            clientAssetMapping[client][underlyingTokens[i]].lstRestakedAmount = underlyingAmounts[i];
            emit UpdateClientLSTRestakedAmount(client, underlyingTokens[i], underlyingAmounts[i]);
        }

        clientData.nativeRestakedAmount = underlyingAmounts[totalStrategies - 1];
        emit UpdateClientNativeRestakedAmount(client, clientData.nativeRestakedAmount);
    }

    function _setEigenPod(address client, ClientData storage clientData) internal returns (address eigenPod) {
        eigenPod = _fetchEigenPod(client);

        if (eigenPod != address(0) && clientData.eigenPod == address(0)) {
            registeredPod[eigenPod] = true;
            clientData.eigenPod = eigenPod;
            _updateMLRTWalletEigenPod(clientData, eigenPod);
            emit EigenPodSet(client, eigenPod);
        }
    }

    function _fetchEigenPod(address client) internal view returns (address) {
        IEigenPodManager eigenPodManager = _getEigenPodManager();
        return address(eigenPodManager.getPod(client));
    }

    function _updateMLRTWalletEigenPod(ClientData storage clientData, address eigenPod) internal {
        if (clientData.mlrtWallet == address(0)) return;

        address mlrtWalletEigenPod = IMLRTWallet(clientData.mlrtWallet).eigenPod();
        if (mlrtWalletEigenPod != address(0)) {
            revert EigenPodAlreadySet();
        }
        IMLRTWallet(clientData.mlrtWallet).setEigenPod(eigenPod);
    }

    function _getEigenPodManager() internal view returns (IEigenPodManager) {
        return IEigenPodManager(eigenpieConfig.getContract(EigenpieConstants.EIGENPOD_MANAGER));
    }

    function _getPodShares(address client) internal view returns (uint256 podShares) {
        IEigenPodManager eigenPodManager = _getEigenPodManager();
        return uint256(eigenPodManager.podOwnerShares(client));
    }

    function _getStrategyShares(address client)
        internal
        view
        returns (address[] memory underlyingTokens, uint256[] memory underlyingAmounts, uint256 supportedAssetsCount)
    {
        address[] memory supportedAssetList = eigenpieConfig.getSupportedAssetList();
        supportedAssetsCount = supportedAssetList.length;

        underlyingTokens = new address[](supportedAssetsCount);
        underlyingAmounts = new uint256[](supportedAssetsCount);

        uint256 pointer = 0;
        for (uint256 i = 0; i < supportedAssetsCount; i++) {
            address strategy = eigenpieConfig.assetStrategy(supportedAssetList[i]);
            if (strategy != address(0)) {
                uint256 strategyShare = IStrategy(strategy).userUnderlyingView(client);
                underlyingTokens[pointer] = supportedAssetList[i];
                underlyingAmounts[pointer] = strategyShare;
                pointer++;
            }
        }
    }
}
