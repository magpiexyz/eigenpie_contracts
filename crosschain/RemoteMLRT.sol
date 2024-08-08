// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

import { EigenpieConstants } from "../utils/EigenpieConstants.sol";
import { IEigenpieConfig } from "../utils/EigenpieConfigRoleChecker.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title The contract for remote mLRT token
/// @author Eigenpie Team
contract RemoteMLRT is
    OwnableUpgradeable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable
{
    uint256 public exchangeRateToLST;
    IEigenpieConfig public eigenpieConfig;

    event LSTExchangeRateUpdated(address indexed caller, uint256 newExchangeRate);
    event EigenpieConfigSet(address eigenpieConfigAddr);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyPriceProvider() {
        if (!IAccessControl(address(eigenpieConfig)).hasRole(EigenpieConstants.PRICE_PROVIDER_ROLE, msg.sender)) {
            revert IEigenpieConfig.CallerNotEigenpieConfigPriceProvider();
        }
        _;
    }

    /// @dev Initializes the contract
    /// @param admin Admin address
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        address _eigenpieConfigAddr,
        uint256 exchangeRate
    )
        external
        initializer
    {
        eigenpieConfig = IEigenpieConfig(_eigenpieConfigAddr);
        exchangeRateToLST = exchangeRate;
        __ERC20_init(name, symbol);
        __ERC20Burnable_init();
        __Pausable_init();
        __Ownable_init();
        __ERC20Permit_init(symbol);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function mint(address to, uint256 amount) public onlyRole(EigenpieConstants.MINTER_ROLE) {
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal virtual override whenNotPaused {
        super._mint(to, amount);
    }

    function burn(address to, uint256 amount) public onlyRole(EigenpieConstants.BURNER_ROLE) {
        _burn(to, amount);
    }

    function _burn(address to, uint256 amount) internal virtual override whenNotPaused {
        super._burn(to, amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function updateExchangeRateToLST(uint256 _newRate) external onlyPriceProvider {
        exchangeRateToLST = _newRate;

        emit LSTExchangeRateUpdated(msg.sender, _newRate);
    }

    function config(address _eigenpieConfigAddr, uint256 initialRate) external onlyOwner {
        eigenpieConfig = IEigenpieConfig(_eigenpieConfigAddr);
        exchangeRateToLST = initialRate;

        emit EigenpieConfigSet(_eigenpieConfigAddr);
        emit LSTExchangeRateUpdated(msg.sender, initialRate);
    }
}
