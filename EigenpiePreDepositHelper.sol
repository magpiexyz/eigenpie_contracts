// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./utils/UtilLib.sol";
import "./utils/EigenpieConfigRoleChecker.sol";
import "./interfaces/IMintableERC20.sol";
import { IMLRT } from "./interfaces/IMLRT.sol";

/// @title EigenpiePreDepositHelper - Deposit Pool Contract for LSTs
/// @notice Handles LST asset deposits
contract EigenpiePreDepositHelper is PausableUpgradeable, EigenpieConfigRoleChecker, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount; // minted mlrAmount from user's preDeposited
        uint256 claimed;
    }

    mapping(bytes32 => mapping(address => UserInfo)) public userInfo; // Cycle + Key  = bytes32 = > asset
    mapping(uint256 => bool) public claimableCycles;
    uint256 public currentCycle;

    event UserPreDeposit(address indexed user, address indexed asset, uint256 amount, uint256 cycle);
    event Claim(address indexed user, address indexed asset, uint256 amount, uint256 cycle);
    event CycleModified(bool claimable, uint256 cycle);

    error ClaimCycleNotStarted();
    error InvalidCaller();
    error InvalidAmount();
    error CycleNotSet();

    event WithdrawPreDeposit(uint256 _cycle, address _user, address _asset, address _receipt, uint256 _mlrtAmount);

    modifier onlyEigenpieStaking() {
        address eigenpieStaking = eigenpieConfig.getContract(EigenpieConstants.EIGENPIE_STAKING);
        if (msg.sender != eigenpieStaking) revert InvalidCaller();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address eigenpieConfigAddr) external initializer {
        UtilLib.checkNonZeroAddress(eigenpieConfigAddr);

        __Pausable_init();
        __ReentrancyGuard_init();

        eigenpieConfig = IEigenpieConfig(eigenpieConfigAddr);
        emit UpdatedEigenpieConfig(eigenpieConfigAddr);
    }

    /// @notice Generates a unique key for each user and cycle combination.
    function getCycleUserKey(uint256 _cycle, address _user) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_cycle, _user));
    }

    /// @notice Retrieves the deposit and claim information for a user in a specific cycle and asset.
    function getUserCycleInfo(
        uint256 _cycle,
        address _user,
        address _asset
    )
        external
        view
        returns (uint256 amount, uint256 claimed)
    {
        bytes32 cycleUserKey = getCycleUserKey(_cycle, _user);
        UserInfo memory user = userInfo[cycleUserKey][_asset];
        return (user.amount, user.claimed);
    }

    function withdraw(
        uint256 _cycle,
        address _user,
        address _asset,
        address _receipt,
        uint256 _mlrtAmount
    )
        external
        onlyEigenpieStaking
        nonReentrant
        whenNotPaused
    {
        bytes32 cycleUserKey = getCycleUserKey(_cycle, _user);
        UserInfo storage user = userInfo[cycleUserKey][_asset];
        if (user.amount < _mlrtAmount) revert InvalidAmount();

        emit WithdrawPreDeposit(_cycle, _user, _asset, _receipt, _mlrtAmount);

        user.amount -= _mlrtAmount;
        IMintableERC20(_receipt).burnFrom(address(this), _mlrtAmount);
    }

    /// @notice Records a user's deposit for a specific asset in the current cycle.
    function feedUserDeposit(
        address _for,
        address _asset,
        uint256 _amount
    )
        external
        onlyEigenpieStaking
        nonReentrant
        whenNotPaused
    {
        if (_amount == 0) revert InvalidAmount();
        if (currentCycle == 0) revert CycleNotSet();

        bytes32 cycleUserKey = getCycleUserKey(currentCycle, _for);
        UserInfo storage user = userInfo[cycleUserKey][_asset];
        user.amount += _amount;
        emit UserPreDeposit(_for, _asset, _amount, currentCycle);
    }

    /// @notice Allows users to claim their deposited MLRT Tokens for multiple cycles and assets.
    /// @dev Iterates through each cycle and asset, processing claims accordingly.
    function userClaim(uint256[] calldata _cycles, address[] calldata _assets) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < _cycles.length;) {
            if (!claimableCycles[_cycles[i]]) revert ClaimCycleNotStarted();
            for (uint256 j = 0; j < _assets.length;) {
                bytes32 cycleUserKey = getCycleUserKey(_cycles[i], msg.sender);
                UserInfo storage user = userInfo[cycleUserKey][_assets[j]];
                uint256 amount = user.amount - user.claimed;
                if (amount > 0) {
                    address receipt = eigenpieConfig.mLRTReceiptByAsset(_assets[j]);
                    user.claimed += amount;
                    IERC20(receipt).safeTransfer(msg.sender, amount);
                    emit Claim(msg.sender, _assets[j], amount, _cycles[i]);
                }

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Triggers stopped state. Contract must not be paused.
    function pause() external onlyEigenpieManager {
        _pause();
    }

    /// @dev Returns to normal state. Contract must be paused
    function unpause() external onlyDefaultAdmin {
        _unpause();
    }

    /// @notice Sets the current cycle as claimable or not.
    function setCycleClaimable(bool _isClaim) external onlyDefaultAdmin {
        claimableCycles[currentCycle] = _isClaim;
        emit CycleModified(_isClaim, currentCycle);
    }

    /// @notice Advances to the next cycle.
    function advanceCycle() external onlyDefaultAdmin {
        currentCycle++;
    }
}
