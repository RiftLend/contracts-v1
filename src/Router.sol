// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {ILendingPoolCollateralManager} from "src/interfaces/ILendingPoolCollateralManager.sol";
import {ISuperAsset} from "src/interfaces/ISuperAsset.sol";
import {IRToken} from "src/interfaces/IRToken.sol";
import {IRVaultAsset} from "src/interfaces/IRVaultAsset.sol";
import {IVariableDebtToken} from "src/interfaces/IVariableDebtToken.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import "src/interfaces/ILendingPool.sol";

import {Initializable} from "@solady/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {ReserveLogic} from "src/libraries/logic/ReserveLogic.sol";
import {SuperPausable} from "src/interop-std/src/utils/SuperPausable.sol";
import {EventValidator, ValidationMode, Identifier} from "src/libraries/EventValidator.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";
import {ReserveLogic} from "src/libraries/logic/ReserveLogic.sol";
import {MessagingFee} from "src/libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {console} from "forge-std/console.sol";

contract Router is Initializable, SuperPausable {
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;

    bytes2 internal constant UPDATE_RATES_AND_STATES_MASK = bytes2(uint16(3));
    uint256 internal constant ROUTER_REVISION = 0x1;

    ILendingPool internal lendingPool;
    address internal addressesProvider;
    address internal eventValidator;
    address internal relayer;
    uint8 internal pool_type;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Custom Erros                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NOT_RELAYER();
    error ONLY_LP_CONFIGURATOR();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  External Functions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Function is invoked by the proxy contract to initialize the Router contract
     * @param _lendingPool The address of the LendingPool contract
     * @param _addressesProvider The address of the LendingPoolAddressesProvider contract
     */
    function initialize(address _lendingPool, address _addressesProvider, address _eventValidator)
        external
        initializer
    {
        lendingPool = ILendingPool(_lendingPool);
        addressesProvider = _addressesProvider;
        eventValidator = _eventValidator;
        pool_type = ILendingPool(lendingPool).pool_type();
    }

    function dispatch(
        ValidationMode _mode,
        Identifier[] calldata _identifier,
        bytes[] calldata _data,
        bytes calldata _proof,
        uint256[] calldata _logIndex
    ) external whenNotPaused {
        if (ILendingPoolAddressesProvider(addressesProvider).getRelayerStatus(msg.sender) != true) revert NOT_RELAYER();

        for (uint256 i = 0; i < _identifier.length; i++) {
            if (_mode != ValidationMode.CUSTOM) {
                EventValidator(eventValidator).validate(_mode, _identifier[i], _data, _logIndex, _proof);
            }

            _dispatch(_identifier[i], _data[i]);
        }
    }

    function _dispatch(Identifier calldata _identifier, bytes calldata _data) internal {
        bytes32 selector = abi.decode(_data[:32], (bytes32));

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                     DEPOSIT DISPATCH                       */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == ILendingPool.Deposit.selector && _identifier.chainId != block.chainid) {
            (DataTypes.DepositEventParams memory params) = abi.decode(_data[32:], (DataTypes.DepositEventParams));

            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(params.reserve);
            lendingPool.updateStates(params.reserve, params.amount, 0, UPDATE_RATES_AND_STATES_MASK);
            IRToken(reserve.rTokenAddress).updateCrossChainBalance(
                params.onBehalfOf, params.amount, params.amountScaled, params.mintMode
            );
        }
        if (selector == ILendingPool.CrossChainDeposit.selector) {
            (
                uint256 fromChainId,
                address sender,
                address asset,
                uint256 amount,
                address onBehalfOf,
                uint16 referralCode
            ) = abi.decode(_data[32:], (uint256, address, address, uint256, address, uint16));
            if (fromChainId == block.chainid) {
                lendingPool.deposit(sender, asset, amount, onBehalfOf, referralCode);
            }
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    WITHDRAW DISPATCH                       */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        if (selector == ILendingPool.Withdraw.selector && _identifier.chainId != block.chainid) {
            (DataTypes.WithdrawEventParams memory params) = abi.decode(_data[32:], (DataTypes.WithdrawEventParams));
            // params.reserve is rvault asset

            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(params.reserve);
            lendingPool.updateStates(params.reserve, 0, params.amount, UPDATE_RATES_AND_STATES_MASK);
            IRToken(reserve.rTokenAddress).updateCrossChainBalance(
                params.user, params.amount, params.amountScaled, params.mode
            );
        }

        if (selector == ILendingPool.CrossChainWithdraw.selector) {
            (DataTypes.CrosschainWithdrawData memory params) =
                abi.decode(_data[32:], (DataTypes.CrosschainWithdrawData));
            if (params.fromChainId == block.chainid) {
                lendingPool.withdraw(params.sender, params.asset, params.amount, params.to, params.toChainId);
            }
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    BORROW DISPATCH                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == ILendingPool.Borrow.selector && _identifier.chainId != block.chainid) {
            DataTypes.BorrowEventParams memory params = abi.decode(_data[32:], (DataTypes.BorrowEventParams));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(params.reserve);
            lendingPool.updateStates(params.reserve, 0, params.amount, UPDATE_RATES_AND_STATES_MASK);
            IVariableDebtToken(reserve.variableDebtTokenAddress).updateCrossChainBalance(
                params.onBehalfOf, params.amountScaled, params.mintMode
            );
        }

        if (selector == ILendingPool.CrossChainBorrow.selector) {
            (DataTypes.CrosschainBorrowData memory params) = abi.decode(_data[32:], (DataTypes.CrosschainBorrowData));

            if (params.borrowFromChainId == block.chainid) {
                lendingPool.borrow(
                    params.sender,
                    params.asset,
                    params.amount,
                    params.onBehalfOf,
                    params.sendToChainId,
                    params.referralCode
                );
            }
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    REPAY DISPATCH                          */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == ILendingPool.Repay.selector && _identifier.chainId != block.chainid) {
            // emit Repay(asset, paybackAmount, onBehalfOf, sender, mode, amountBurned);

            (DataTypes.RepayEventParams memory params) = abi.decode(_data[32:], (DataTypes.RepayEventParams));
            address rVaultAsset = lendingPool.getRVaultAssetOrRevert(params.reserve);
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(rVaultAsset);
            lendingPool.updateStates(rVaultAsset, params.amount, 0, UPDATE_RATES_AND_STATES_MASK);
            IVariableDebtToken(reserve.variableDebtTokenAddress).updateCrossChainBalance(
                params.user, params.amountBurned, params.mode
            );
        } else if (selector == ILendingPool.CrossChainRepay.selector) {
            (DataTypes.CrosschainRepayData memory params) = abi.decode(_data[32:], (DataTypes.CrosschainRepayData));
            if (params.fundChainId == block.chainid) {
                address rVaultAsset = lendingPool.getRVaultAssetOrRevert(params.asset);
                address reserve_superAsset = lendingPool.getReserveData(rVaultAsset).superAsset;

                IERC20(params.asset).safeTransferFrom(params.sender, address(this), params.amount);
                if (pool_type == 1) {
                    // TODO: remove redundant approves for gas savings , by calling each time lp.setRVaultAssetForUnderlying is called
                    IERC20(params.asset).approve(reserve_superAsset, params.amount);
                    ISuperAsset(reserve_superAsset).deposit(address(this), params.amount);
                    IERC20(reserve_superAsset).approve(rVaultAsset, params.amount);
                }
                IRVaultAsset(rVaultAsset).deposit(params.amount, address(this));

                MessagingFee memory fee;
                if (params.debtChainId != block.chainid) {
                    (, fee) =
                        IRVaultAsset(rVaultAsset).getFeeQuote(params.onBehalfOf, params.debtChainId, params.amount);
                }
                IRVaultAsset(rVaultAsset).bridge{value: fee.nativeFee}(
                    address(lendingPool), params.debtChainId, params.amount
                );
                emit ILendingPool.CrossChainRepayFinalize(
                    DataTypes.CrosschainRepayFinalizeData(
                        params.debtChainId, params.sender, params.onBehalfOf, params.amount, params.asset
                    )
                );
            }
        } else if (selector == ILendingPool.CrossChainRepayFinalize.selector) {
            (DataTypes.CrosschainRepayFinalizeData memory params) =
                abi.decode(_data[32:], (DataTypes.CrosschainRepayFinalizeData));
            if (params.debtChainId == block.chainid) {
                lendingPool.repay(params.sender, params.onBehalfOf, params.asset, params.amount);
            }
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    LIQUIDATION CALL DISPATCH               */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        if (selector == ILendingPoolCollateralManager.LiquidationCall.selector && _identifier.chainId != block.chainid)
        {
            (DataTypes.LiquidationCallEventParams memory params) =
                abi.decode(_data[32:], (DataTypes.LiquidationCallEventParams));

            DataTypes.ReserveData memory debtReserve = lendingPool.getReserveData(params.debtAsset);
            IVariableDebtToken(debtReserve.variableDebtTokenAddress).updateCrossChainBalance(
                params.user, params.variableDebtBurned, 2
            );
            lendingPool.updateStates(params.debtAsset, 0, params.debtToCover, UPDATE_RATES_AND_STATES_MASK);
            if (!params.receiveRToken) {
                DataTypes.ReserveData memory collateralReserve = lendingPool.getReserveData(params.collateralAsset);
                lendingPool.updateStates(
                    params.collateralAsset, 0, params.liquidatedCollateralAmount, UPDATE_RATES_AND_STATES_MASK
                );
                IRToken(collateralReserve.rTokenAddress).updateCrossChainBalance(
                    params.user, params.liquidatedCollateralAmount, params.collateralRTokenBurned, 2
                );
            } else {
                DataTypes.ReserveData memory collateralReserve = lendingPool.getReserveData(params.collateralAsset);
                lendingPool.updateStates(
                    params.collateralAsset, 0, params.liquidatedCollateralAmount, UPDATE_RATES_AND_STATES_MASK
                );
                IRToken(collateralReserve.rTokenAddress).updateCrossChainBalance(
                    params.liquidator, params.liquidatedCollateralAmount, params.liquidatorSentScaled, 1
                );
            }
        }

        if (selector == ILendingPool.CrossChainLiquidationCall.selector) {
            (DataTypes.CrosschainLiquidationCallData memory params) =
                abi.decode(_data[32:], (DataTypes.CrosschainLiquidationCallData));
            if (params.chainId == block.chainid) {
                lendingPool.liquidationCall(params);
            }
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    FLASHLOAN DISPATCH                      */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == ILendingPool.FlashLoan.selector) {
            (DataTypes.FlashLoanEventParams memory params) = abi.decode(_data[32:], (DataTypes.FlashLoanEventParams));
            if (params.chainId != block.chainid) {
                lendingPool.updateStates(params.asset, 0, params.amount, UPDATE_RATES_AND_STATES_MASK);
            }
        }

        if (selector == ILendingPool.CrossChainInitiateFlashloan.selector) {
            (, DataTypes.InitiateFlashloanParams memory initiateFlashloanParams) =
                abi.decode(_data, (bytes32, DataTypes.InitiateFlashloanParams));

            address sender = initiateFlashloanParams.sender;
            DataTypes.FlashloanParams memory flashloanParams = initiateFlashloanParams.flashloanParams;

            if (flashloanParams.chainid == block.chainid) {
                address[] memory assets = new address[](1);
                uint256[] memory amounts = new uint256[](1);
                uint256[] memory modes = new uint256[](1);
                assets[0] = flashloanParams.asset;
                amounts[0] = flashloanParams.amount;
                modes[0] = flashloanParams.mode;

                // Execute the flashloan with the decoded parameters
                lendingPool.flashLoan(
                    sender,
                    flashloanParams.receiverAddress,
                    assets,
                    amounts,
                    modes,
                    flashloanParams.onBehalfOf,
                    flashloanParams.params,
                    flashloanParams.referralCode
                );
            }
        }
    }

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve across multiple chains
     * @param asset The address of the underlying asset to deposit
     * @param amounts Array of amounts to deposit per chain
     * @param onBehalfOf Address that will receive the rTokens
     * @param referralCode Code used to register the integrator originating the operation
     * @param chainIds Array of chain IDs where the deposits should be made
     */
    function deposit(
        address asset,
        uint256[] calldata amounts,
        address onBehalfOf,
        uint16 referralCode,
        uint256[] calldata chainIds
    ) external whenNotPaused {
        for (uint256 i = 0; i < chainIds.length; i++) {
            emit ILendingPool.CrossChainDeposit(
                DataTypes.CrosschainDepositData(chainIds[i], msg.sender, asset, amounts[i], onBehalfOf, referralCode)
            );
        }
    }

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent rTokens owned
     * @param asset The address of the underlying asset to withdraw
     * @param amounts Array of amounts to withdraw per chain
     * @param to Address that will receive the underlying
     * @param chainIds Array of chain IDs where the withdrawals should be made
     */
    function withdraw(
        address asset,
        uint256[] calldata amounts,
        address to,
        uint256 toChainId,
        uint256[] calldata chainIds
    ) external whenNotPaused {
        for (uint256 i = 0; i < chainIds.length; i++) {
            emit ILendingPool.CrossChainWithdraw(
                DataTypes.CrosschainWithdrawData(chainIds[i], msg.sender, asset, amounts[i], to, toChainId)
            );
        }
    }

    // Frontend would need to calculate how much to borrow on each chain where the user has collateral ...
    /**
     * @dev Allows users to borrow across multiple chains, provided they have enough collateral
     * @param asset The address of the underlying asset to borrow
     * @param amounts Array of amounts to borrow per chain
     * @param referralCode Code used to register the integrator originating the operation
     * @param onBehalfOf Address that will receive the debt
     * @param chainIds Array of chain IDs where to borrow from
     */
    function borrow(
        address asset,
        uint256[] calldata amounts,
        uint16 referralCode,
        address onBehalfOf,
        uint256 sendToChainId,
        uint256[] calldata chainIds
    ) external whenNotPaused {
        for (uint256 i = 0; i < chainIds.length; i++) {
            emit ILendingPool.CrossChainBorrow(
                DataTypes.CrosschainBorrowData(
                    chainIds[i], sendToChainId, msg.sender, asset, amounts[i], onBehalfOf, referralCode
                )
            );
        }
    }

    /**
     * @dev Repays a borrowed `amount` on a specific reserve across multiple chains, burning the equivalent debt tokens owned
     * @param _asset The address of the borrowed underlying asset previously borrowed
     * @param _onBehalfOf Address of the user who will get their debt reduced/removed
     * @param _repayParams Array of repay parameters including the amount to repay per chain, the debt chain ID, and the fund chain ID
     * emits CrossChainRepay event
     */
    function repay(address _asset, address _onBehalfOf, DataTypes.RepayParam[] calldata _repayParams)
        external
        whenNotPaused
    {
        for (uint256 i = 0; i < _repayParams.length; i++) {
            emit ILendingPool.CrossChainRepay(
                DataTypes.CrosschainRepayData(
                    _repayParams[i].fundChainId,
                    msg.sender,
                    _asset,
                    _repayParams[i].amount,
                    _onBehalfOf,
                    _repayParams[i].debtChainId
                )
            );
        }
    }

    /**
     * @dev Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover, from each chain
     * @param chainIds Array of chain IDs where the liquidation should be executed
     * @param receiveRToken `true` if the liquidators wants to receive the collateral rTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     *
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256[] calldata debtToCover,
        uint256[] calldata chainIds,
        bool receiveRToken
    ) external whenNotPaused {
        // DataTypes.ReserveData memory reserve = lendingPool.getReserveData(debtAsset);
        for (uint256 i = 0; i < chainIds.length; i++) {
            emit ILendingPool.CrossChainLiquidationCall(
                DataTypes.CrosschainLiquidationCallData(
                    chainIds[i], msg.sender, collateralAsset, debtAsset, user, debtToCover[i], receiveRToken
                )
            );
        }
    }

    function initiateFlashLoan(DataTypes.FlashloanParams[] calldata flashloanParams) external whenNotPaused {
        for (uint256 i = 0; i < flashloanParams.length; i++) {
            emit ILendingPool.CrossChainInitiateFlashloan(
                DataTypes.InitiateFlashloanParams(msg.sender, flashloanParams[i])
            );
        }
    }

    /**
     * @dev Set the _pause state of a reserve
     * - Only callable by the LendingPoolConfigurator contract
     * @param val `true` to pause the reserve, `false` to un-pause it
     */
    function setPause(bool val) external {
        if (ILendingPoolAddressesProvider(addressesProvider).getLendingPoolConfigurator() != msg.sender) {
            revert ONLY_LP_CONFIGURATOR();
        }
        if (val) _pause();
        else _unpause();
    }
}
