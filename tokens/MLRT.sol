// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "../utils/UtilLib.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig, EigenpieConstants } from "../utils/EigenpieConfigRoleChecker.sol";
import { IMLRT } from "../interfaces/IMLRT.sol";
import { IPriceProvider } from "../interfaces/IPriceProvider.sol";

import { ERC20Upgradeable, Initializable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/// @title mLRT token Contract. A generic token contract for Liquid Wrapper for staked LST through Eigenpie
/// @author Eigenpie Team
/// @notice The ERC20 contract for the mLRT token
contract MLRT is Initializable, EigenpieConfigRoleChecker, ERC20Upgradeable, PausableUpgradeable {
    address public underlyingAsset;
    uint256 public exchangeRateToLST;

    event LSTExchangeRateUpdated(address indexed caller, uint256 newExchangeRate);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param asset underlying asset
    /// @param eigenpieConfigAddr Eigenpie config address
    /// @param name name of the MLRT token
    /// @param symbol symbol of the MLRT token
    function initialize(
        address asset,
        address eigenpieConfigAddr,
        string calldata name,
        string calldata symbol
    )
        external
        initializer
    {
        UtilLib.checkNonZeroAddress(asset);
        UtilLib.checkNonZeroAddress(eigenpieConfigAddr);

        __ERC20_init(name, symbol);
        __Pausable_init();

        eigenpieConfig = IEigenpieConfig(eigenpieConfigAddr);
        underlyingAsset = asset;

        exchangeRateToLST = 1 ether;

        emit UpdatedEigenpieConfig(eigenpieConfigAddr);
    }

    /*//////////////////////////////////////////////////////////////
                            view functions
    //////////////////////////////////////////////////////////////*/

    function exchangeRateToNative() external view returns (uint256) {
        address priceProvider = eigenpieConfig.getContract(EigenpieConstants.PRICE_PROVIDER);

        uint256 exchangeRateETH = IPriceProvider(priceProvider).getAssetPrice(underlyingAsset);

        return exchangeRateToLST * exchangeRateETH / 1 ether;
    }

    /*//////////////////////////////////////////////////////////////
                            Write functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints EGETH when called by an authorized caller
    /// @param to the account to mint to
    /// @param amount the amount of EGETH to mint
    function mint(address to, uint256 amount) external onlyMinter whenNotPaused {
        _mint(to, amount);
    }

    /// @notice Burns EGETH when called by an authorized caller
    /// @param account the account to burn from
    /// @param amount the amount of EGETH to burn
    function burnFrom(address account, uint256 amount) external onlyBurner whenNotPaused {
        _burn(account, amount);
    }

    /// @dev Triggers stopped state.
    /// @dev Only callable by Eigenpie config manager. Contract must NOT be paused.
    function pause() external onlyEigenpieManager {
        _pause();
    }

    /// @notice Returns to normal state.
    /// @dev Only callable by the admin. Contract must be paused
    function unpause() external onlyDefaultAdmin {
        _unpause();
    }

    /// @notice Updates the MLRT to LST rate
    /// @dev only callable by the Price Provider
    /// @param _newRate the new Eigenpie config contract
    function updateExchangeRateToLST(uint256 _newRate) external onlyPriceProvider {
        exchangeRateToLST = _newRate;

        emit LSTExchangeRateUpdated(msg.sender, _newRate);
    }
}
