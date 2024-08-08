// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

interface IEigenpieStaking {
    //errors
    error TokenTransferFailed();
    error InvalidAmountToDeposit();
    error NotEnoughAssetToTransfer();
    error MaximumDepositLimitReached();
    error MaximumNodeDelegatorLimitReached();
    error InvalidMaximumNodeDelegatorLimit();
    error MinimumAmountToReceiveNotMet();
    error InvalidIndex();
    error NativeTokenTransferFailed();
    error InvalidCaller();
    error LengthMismatch();
    error OnlyWhenPredeposit();

    //events
    event MaxNodeDelegatorLimitUpdated(uint256 maxNodeDelegatorLimit);
    event NodeDelegatorAddedinQueue(address[] nodeDelegatorContracts);
    event AssetDeposit(
        address indexed depositor,
        address indexed asset,
        uint256 depositAmount,
        address indexed referral,
        uint256 mintedAmount,
        bool isPreDepsoit
    );

    event MinAmountToDepositUpdated(uint256 minAmountToDeposit);
    event PreDepositHelperChanged(address oldPreDepositHelper, address newPreDepositHelper);
    event PreDepositStatusChanged(bool newIsPreDeposit);

    struct PoolInfo {
        address mlrtReceipt;
    }

    function depositAsset(address asset, uint256 depositAmount, uint256 minRec, address referral) external payable;

    function getTotalAssetDeposits(address asset) external view returns (uint256);

    function getAssetCurrentLimit(address asset) external view returns (uint256);

    function addNodeDelegatorContractToQueue(address[] calldata nodeDelegatorContract) external;

    function transferAssetToNodeDelegator(uint256 ndcIndex, address asset, uint256 amount) external;

    function updateMaxNodeDelegatorLimit(uint256 maxNodeDelegatorLimit) external;

    function getNodeDelegatorQueue() external view returns (address[] memory);

    function getAssetDistributionData(address asset)
        external
        view
        returns (uint256 assetLyingInDepositPool, uint256 assetLyingInNDCs, uint256 assetStakedInEigenLayer);
}
