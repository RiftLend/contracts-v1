// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ILendingPoolAddressesProvider} from "./ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "./ILendingPool.sol";
import "../interfaces/ICrossL2Inbox.sol";
import {IFlashLoanReceiver} from "src/interfaces/IFlashLoanReceiver.sol";

import {DataTypes} from "../libraries/types/DataTypes.sol";

interface ILendingPool {
    /**
     * @dev Emitted on deposit()
     *
     */
    event Deposit(DataTypes.DepositEventParams params);

    /**
     * @dev Emitted on withdraw()
     *
     */
    event Withdraw(DataTypes.WithdrawEventParams params);

    /**
     * @dev Emitted on borrow() and flashLoan() when debt needs to be opened
     */
    event Borrow(DataTypes.BorrowEventParams params);

    /**
     * @dev Emitted on repay()
     */
    event Repay(DataTypes.RepayEventParams params);

    /**
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address of the user enabling the usage as collateral
     *
     */
    event ReserveUsedAsCollateralEnabled(address reserve, address user);

    /**
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address of the user enabling the usage as collateral
     *
     */
    event ReserveUsedAsCollateralDisabled(address reserve, address user);

    /**
     * @dev Emitted on flashLoan()
     */
    event FlashLoan(DataTypes.FlashLoanEventParams params);

    // Events using structured data
    event CrossChainDeposit(DataTypes.CrosschainDepositData deposit);

    event CrossChainLiquidationCall(DataTypes.CrosschainLiquidationCallData liquidation);

    event CrossChainBorrow(DataTypes.CrosschainBorrowData borrow);

    event CrossChainWithdraw(DataTypes.CrosschainWithdrawData withdraw);

    event CrossChainRepay(DataTypes.CrosschainRepayData repay);

    event CrossChainRepayFinalize(DataTypes.CrosschainRepayFinalizeData repayFinalize);

    event CrossChainInitiateFlashloan(DataTypes.InitiateFlashloanParams flashloanParams);

    /**
     * @dev Functions to deposit/withdraw into the reserve
     */
    function deposit(address sender, address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function withdraw(address sender, address asset, uint256 amount, address to, uint256 toChainId) external;

    /**
     * @dev Functions to borrow from the reserve
     */
    function borrow(
        address sender,
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint256 sendToChainId,
        uint16 referralCode
    ) external;

    function repay(address sender, address onBehalfOf, address asset, uint256 amount) external;

    function setRvaultAssetForUnderlying(address asset, address rVaultAsset) external;

    function liquidationCall(DataTypes.CrosschainLiquidationCallData memory params) external;

    function updateStates(address asset, uint256 depositAmount, uint256 withdrawAmount, bytes2 mask) external;

    function initReserve(
        address asset,
        address superchainAsset,
        address rTokenAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external;

    function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress) external;

    function setConfiguration(address asset, uint256 configuration) external;

    function setConfiguration(Identifier calldata _identifier, bytes calldata _data) external;

    function getConfiguration(address asset) external view returns (DataTypes.ReserveConfigurationMap memory);

    function getUserConfiguration(address user) external view returns (DataTypes.UserConfigurationMap memory);

    function getReserveNormalizedIncome(address asset) external view returns (uint256);

    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256);

    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);

    function getAddressesProvider() external view returns (ILendingPoolAddressesProvider);

    function getRVaultAssetOrRevert(address asset) external view returns (address rVaultAsset);

    function _flashLoanPremiumTotal() external view returns (uint256);

    function _maxNumberOfReserves() external view returns (uint256);

    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external;

    function setPause(bool val) external;

    function paused() external view returns (bool);

    function flashLoan(
        address sender,
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    function pool_type() external view returns (uint8);
    function getReserveById(uint256 id) external view returns (address asset);
}
