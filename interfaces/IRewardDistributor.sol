// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

interface IRewardDistributor {
    struct RewardDestinations {
        uint256 value; // allocation denominated by DENOMINATOR
        address to;
        bool isAddress; // if true, simply transfer token over
        bool needWrap; // to wrap if native token
    }

    error InvalidFeePercentage();
    error InvalidIndex();

    event RewardDestinationAdded(
        uint256 indexed index, uint256 value, address indexed to, bool isAddress, bool needWrap
    );
    event RewardDestinationUpdated(
        uint256 indexed index, uint256 value, address indexed to, bool isAddress, bool needWrap
    );
    event RewardDestinationRemoved(uint256 indexed index);
}
