// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { EigenpieConstants } from "./EigenpieConstants.sol";

/// @title UtilLib - Utility library
/// @notice Utility functions
library UtilLib {
    error ZeroAddressNotAllowed();

    /// @dev zero address check modifier
    /// @param address_ address to check
    function checkNonZeroAddress(address address_) internal pure {
        if (address_ == address(0)) revert ZeroAddressNotAllowed();
    }

    function isNativeToken(address addr) internal pure returns (bool) {
        return addr == EigenpieConstants.PLATFORM_TOKEN_ADDRESS;
    }
}
