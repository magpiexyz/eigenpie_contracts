// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "./utils/UtilLib.sol";
import { EigenpieConstants } from "./utils/EigenpieConstants.sol";
import { EigenpieConfigRoleChecker, IEigenpieConfig } from "./utils/EigenpieConfigRoleChecker.sol";
import { IEigenpieEnterprise } from "./interfaces/IEigenpieEnterprise.sol";
import { IMLRTWallet } from "./interfaces/IMLRTWallet.sol";
import { IMLRT } from "./interfaces/IMLRT.sol";
import { IZtakingPool } from "./interfaces/zircuit/IZtakingPool.sol";
import { ISimpleStakingERC20 } from "./interfaces/swell/ISimpleStakingERC20.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract MLRTWallet is IMLRTWallet, EigenpieConfigRoleChecker, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IEigenpieEnterprise public eigenpieEnterprise;

    address public client;
    address public eigenPod;

    // 1st upgrade
    mapping(address => bool) public allowedClientOperators;

    uint256[49] private __gap; // reserve for upgrade

    constructor() {
        _disableInitializers();
    }

    modifier onlyClient() {
        if (msg.sender != client) revert OnlyClient();
        _;
    }

    modifier onlyEigenpieEnterprise() {
        if (msg.sender != address(eigenpieEnterprise)) revert NotAllowedCaller();
        _;
    }

    modifier onlyClientOrAllowedOperator() {
        bool isClient = msg.sender == client;
        bool isAllowedClientOperator = allowedClientOperators[msg.sender];

        if (!isClient && !isAllowedClientOperator) revert NotAllowedCaller();
        _;
    }

    function initialize(
        address _client,
        address _eigenPod,
        address eigenpieConfigAddr,
        address eigenpieEnterpriseAddr
    )
        external
        initializer
    {
        UtilLib.checkNonZeroAddress(eigenpieConfigAddr);
        UtilLib.checkNonZeroAddress(eigenpieEnterpriseAddr);

        client = _client;
        eigenPod = _eigenPod;
        eigenpieConfig = IEigenpieConfig(eigenpieConfigAddr);
        eigenpieEnterprise = IEigenpieEnterprise(eigenpieEnterpriseAddr);
    }

    /*//////////////////////////////////////////////////////////////
                            Read functions
    //////////////////////////////////////////////////////////////*/

    function restakedLess(address underlyingToken) external returns (uint256 ethLess, uint256 shouldBurn) {
        return eigenpieEnterprise.restakedLess(client, underlyingToken);
    }

    /*//////////////////////////////////////////////////////////////
                            Write functions
    //////////////////////////////////////////////////////////////*/

    function depositToZicruit(
        address mlrt,
        uint256 amount
    )
        external
        whenNotPaused
        nonReentrant
        onlyClientOrAllowedOperator
    {
        IZtakingPool zircuiteStakingPool =
            IZtakingPool(eigenpieConfig.getContract(EigenpieConstants.ZIRCUIT_ZSTAKIGPOOL));
        IERC20(mlrt).safeApprove(address(zircuiteStakingPool), amount);
        zircuiteStakingPool.depositFor(mlrt, address(this), amount);

        emit DepositToZicruit(msg.sender, mlrt, amount);
    }

    function withdrawFromZicruit(address mlrt, uint256 amount) external nonReentrant {
        eigenpieEnterprise.syncClientRestakedAmount(client);
        (bool isPublic) = _checkValidWithdrawCondition(msg.sender, amount, mlrt);

        IZtakingPool zircuiteStakingPool =
            IZtakingPool(eigenpieConfig.getContract(EigenpieConstants.ZIRCUIT_ZSTAKIGPOOL));
        zircuiteStakingPool.withdraw(mlrt, amount);

        if (isPublic) {
            eigenpieEnterprise.burnMLRT(client, mlrt, amount);
        }

        emit WithdrawFromZicruit(msg.sender, mlrt, amount);
    }

    function depositToSwellStaking(
        address mlrt,
        uint256 amount
    )
        external
        whenNotPaused
        nonReentrant
        onlyClientOrAllowedOperator
    {
        ISimpleStakingERC20 swellSimpleStaking =
            ISimpleStakingERC20(eigenpieConfig.getContract(EigenpieConstants.SWELL_SIMPLE_STAKING));
        IERC20(mlrt).safeApprove(address(swellSimpleStaking), amount);
        swellSimpleStaking.deposit(IERC20(mlrt), amount, address(this));

        emit DepositToSwellStaking(msg.sender, mlrt, amount);
    }

    function withdrawFromSwellStaking(address mlrt, uint256 amount) external nonReentrant {
        eigenpieEnterprise.syncClientRestakedAmount(client);
        (bool isPublic) = _checkValidWithdrawCondition(msg.sender, amount, mlrt);

        ISimpleStakingERC20 swellSimpleStaking =
            ISimpleStakingERC20(eigenpieConfig.getContract(EigenpieConstants.SWELL_SIMPLE_STAKING));
        swellSimpleStaking.withdraw(IERC20(mlrt), amount, address(this));

        if (isPublic) {
            eigenpieEnterprise.burnMLRT(client, mlrt, amount);
        }

        emit WithdrawFromSwellStaking(msg.sender, mlrt, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    function _checkValidWithdrawCondition(
        address caller,
        uint256 amountToWithdraw,
        address mlrt
    )
        internal
        returns (bool fromPublic)
    {
        bool isClient = caller == client;
        bool isClientOperator = allowedClientOperators[caller];
        bool isManager = IAccessControl(address(eigenpieConfig)).hasRole(EigenpieConstants.MANAGER, caller);
        // if client or eigenpie manager calling, then all good
        if (isClient || isClientOperator || isManager) return false;

        address underlyingToken = IMLRT(mlrt).underlyingAsset();
        (, uint256 mlrtShouldBurn) = eigenpieEnterprise.restakedLess(client, underlyingToken);
        if (amountToWithdraw > mlrtShouldBurn) revert PublicWithdrawTooMuch();
        fromPublic = true;
    }

    /*//////////////////////////////////////////////////////////////
                            Admin functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Triggers stopped state. Contract must not be paused.
    function pause() external onlyEigenpieManager {
        _pause();
    }

    /// @dev Returns to normal state. Contract must be paused
    function unpause() external onlyEigenpieManager {
        _unpause();
    }

    function updateAllowedClientOperators(address user, bool allowed) external onlyEigenpieManager {
        allowedClientOperators[user] = allowed;

        emit AllowedClientOperatorUpdated(user, allowed);
    }

    function setEigenPod(address _eigenpod) external onlyEigenpieEnterprise {
        UtilLib.checkNonZeroAddress(_eigenpod);
        eigenPod = _eigenpod;

        emit EigenPodUpdated(client, _eigenpod);
    }
}
