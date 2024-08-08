// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

library EigenpieConstants {
    //contracts
    bytes32 public constant EIGENPIE_STAKING = keccak256("EIGENPIE_STAKING");
    bytes32 public constant EIGEN_STRATEGY_MANAGER = keccak256("EIGEN_STRATEGY_MANAGER");
    bytes32 public constant EIGEN_DELEGATION_MANAGER = keccak256("EIGEN_DELEGATION_MANAGER");
    bytes32 public constant PRICE_PROVIDER = keccak256("PRICE_PROVIDER");
    bytes32 public constant BEACON_DEPOSIT = keccak256("BEACON_DEPOSIT");
    bytes32 public constant EIGENPOD_MANAGER = keccak256("EIGENPOD_MANAGER");
    bytes32 public constant EIGENPIE_PREDEPOSITHELPER = keccak256("EIGENPIE_PREDEPOSITHELPER");
    bytes32 public constant EIGENPIE_REWADR_DISTRIBUTOR = keccak256("EIGENPIE_REWADR_DISTRIBUTOR");
    bytes32 public constant EIGENPIE_DWR = keccak256("EIGENPIE_DWR");

    bytes32 public constant SSVNETWORK_ENTRY = keccak256("SSVNETWORK_ENTRY");
    bytes32 public constant SSV_TOKEN = keccak256("SSV_TOKEN");

    //Roles
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
    bytes32 public constant PRICE_PROVIDER_ROLE = keccak256("PRICE_PROVIDER_ROLE");

    bytes32 public constant ALLOWED_BOT_ROLE = keccak256("ALLOWED_BOT_ROLE");

    // For Native Restaking
    uint256 constant PUBKEY_LENGTH = 48;
    uint256 constant SIGNATURE_LENGTH = 96;
    uint256 constant MAX_VALIDATORS = 100;
    uint256 constant DEPOSIT_AMOUNT = 32 ether;
    uint256 constant GWEI_TO_WEI = 1e9;

    uint256 public constant DENOMINATOR = 10_000;
    address public constant PLATFORM_TOKEN_ADDRESS = 0xeFEfeFEfeFeFEFEFEfefeFeFefEfEfEfeFEFEFEf;
    bytes32 public constant EIGENPIE_WITHDRAW_MANAGER = keccak256("EIGENPIE_WITHDRAW_MANAGER");

    // External Defi
    bytes32 public constant ZIRCUIT_ZSTAKIGPOOL = keccak256("ZIRCUIT_ZSTAKIGPOOL");
    bytes32 public constant SWELL_SIMPLE_STAKING = keccak256("SWELL_SIMPLE_STAKING");
}
