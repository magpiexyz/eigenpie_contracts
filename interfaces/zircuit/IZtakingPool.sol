// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

/// @title Ztaking Pool Interface
/// @notice An interface containing externally accessible functions of the ZtakingPool contract
/// @dev The automatically generated public view functions for the state variables and mappings are not included in the
/// interface
interface IZtakingPool {
    /*//////////////////////////////////////////////////////////////
                            Staker Functions
    //////////////////////////////////////////////////////////////*/

    ///@notice Stake a specified amount of a particular supported token into the Ztaking Pool
    ///@param _token The token to deposit/stake in the Ztaking Pool
    ///@param _for The user to deposit/stake on behalf of
    ///@param _amount The amount of token to deposit/stake into the Ztaking Pool
    function depositFor(address _token, address _for, uint256 _amount) external;

    ///@notice Stake a specified amount of ether into the Ztaking Pool
    ///@param _for The user to deposit/stake on behalf of
    ///@dev the amount deposited is specified by msg.value
    function depositETHFor(address _for) external payable;

    ///@notice Withdraw a specified amount of a particular supported token previously staked into the Ztaking Pool
    ///@param _token The token to withdraw from the Ztaking Pool
    ///@param _amount The amount of token to withdraw from the Ztaking Pool
    function withdraw(address _token, uint256 _amount) external;

    ///@notice Migrate the staked tokens for the caller from the Ztaking Pool to Zircuit
    ///@dev called by the staker
    ///@param _tokens The tokens to migrate to Zircuit from the Ztaking Pool
    ///@param _migratorContract The migrator contract which will initially receive the migrated tokens before moving
    /// them to Zircuit
    ///@param _destination The address which will receive the migrated tokens on Zircuit
    ///@param _signatureExpiry The timestamp at which the signature in _authorizationSignatureFromZircuit expires
    ///@param _authorizationSignatureFromZircuit The authorization signature which is signed by the zircuit signer and
    /// indicates the correct migrator contract
    function migrate(
        address[] calldata _tokens,
        address _migratorContract,
        address _destination,
        uint256 _signatureExpiry,
        bytes memory _authorizationSignatureFromZircuit
    )
        external;

    ///@notice Migrate the staked tokens for the caller from the Ztaking Pool to Zircuit
    ///@param _user The staker to migrate tokens for
    ///@param _tokens The tokens to migrate to Zircuit from the Ztaking Pool
    ///@param _migratorContract The migrator contract which will initially receive the migrated tokens before moving
    /// them to Zircuit
    ///@param _destination The address which will receive the migrated tokens on Zircuit
    ///@param _signatureExpiry The timestamp at which the signature in _authorizationSignatureFromZircuit expires
    ///@param _stakerSignature The signature from the staker authorizing the migration of their tokens
    function migrateWithSig(
        address _user,
        address[] calldata _tokens,
        address _migratorContract,
        address _destination,
        uint256 _signatureExpiry,
        bytes memory _stakerSignature
    )
        external;
}
