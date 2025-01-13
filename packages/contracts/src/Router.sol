// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import "src/interfaces/ILendingPool.sol";
import {ILendingPoolCollateralManager} from "src/interfaces/ILendingPoolCollateralManager.sol";
import {ISuperAsset} from "src/interfaces/ISuperAsset.sol";
import {IRToken} from "src/interfaces/IRToken.sol";
import {IRVaultAsset} from "src/interfaces/IRVaultAsset.sol";
import {IVariableDebtToken} from "src/interfaces/IVariableDebtToken.sol";
import {ISuperchainTokenBridge} from "src/interfaces/ISuperchainTokenBridge.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import "src/interfaces/ILendingPool.sol";
import {ILendingPoolCollateralManager} from "src/interfaces/ILendingPoolCollateralManager.sol";
import {ISuperAsset} from "src/interfaces/ISuperAsset.sol";
import {IRToken} from "src/interfaces/IRToken.sol";
import {IRVaultAsset} from "src/interfaces/IRVaultAsset.sol";
import {IVariableDebtToken} from "src/interfaces/IVariableDebtToken.sol";
import {ISuperchainTokenBridge} from "src/interfaces/ISuperchainTokenBridge.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";

import {Initializable} from "@solady/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {ReserveLogic} from "src/libraries/logic/ReserveLogic.sol";
import {Errors} from "src/libraries/helpers/Errors.sol";
import {SuperPausable} from "src/interop-std/src/utils/SuperPausable.sol";
import {Predeploys} from "src/libraries/Predeploys.sol";
import {EventValidator, ValidationMode, Identifier} from "src/libraries/EventValidator.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";
import {ReserveLogic} from "src/libraries/logic/ReserveLogic.sol";
import {Errors} from "src/libraries/helpers/Errors.sol";
import {SuperPausable} from "src/interop-std/src/utils/SuperPausable.sol";
import {Predeploys} from "src/libraries/Predeploys.sol";
import {EventValidator, ValidationMode, Identifier} from "src/libraries/EventValidator.sol";
import {DataTypes} from "src/libraries/types/DataTypes.sol";

contract Router is Initializable, SuperPausable {
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;

    bytes2 public constant UPDATE_RATES_AND_STATES_MASK = bytes2(uint16(3));
    uint256 public constant ROUTER_REVISION = 0x1;

    ILendingPool public lendingPool;
    ILendingPoolAddressesProvider public addressesProvider;
    address public relayer;
    EventValidator public eventValidator;
    uint8 pool_type;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Modifiers                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyRelayer() {
        _onlyRelayer();
        _;
    }

    function _onlyRelayer() internal view {
        require(addressesProvider.getRelayer() == msg.sender, "!relayer");
    }

    modifier onlyLendingPoolConfigurator() {
        _onlyLendingPoolConfigurator();
        _;
    }

    function _onlyLendingPoolConfigurator() internal view {
        require(
            addressesProvider.getLendingPoolConfigurator() == msg.sender, Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  External Functions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  External Functions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Function is invoked by the proxy contract to initialize the Router contract
     * @param _lendingPool The address of the LendingPool contract
     * @param _addressesProvider The address of the LendingPoolAddressesProvider contract
     */
    function initialize(address _lendingPool, address _addressesProvider, address _eventValidator) public initializer {
        lendingPool = ILendingPool(_lendingPool);
        addressesProvider = ILendingPoolAddressesProvider(_addressesProvider);
        eventValidator = EventValidator(_eventValidator);
        pool_type = ILendingPool(lendingPool).pool_type();
    }

    function dispatch(
        ValidationMode _mode,
        Identifier[] calldata _identifier,
        bytes[] calldata _data,
        bytes calldata _proof,
        uint256[] calldata _logIndex
    ) external onlyRelayer whenNotPaused {
        if (_mode == ValidationMode.CROSS_L2_PROVER_RECEIPT) {
            eventValidator.validate(_mode, _identifier[0], _data, _logIndex, _proof);
        }
        for (uint256 i = 0; i < _identifier.length; i++) {
            if (_mode != ValidationMode.CUSTOM && _mode != ValidationMode.CROSS_L2_PROVER_RECEIPT) {
                eventValidator.validate(_mode, _identifier[i], _data, _logIndex, _proof);
            }
            _dispatch(_identifier[i], _data[i]);
        }
    }

    function _dispatch(Identifier calldata _identifier, bytes calldata _data) internal {
        bytes32 selector = abi.decode(_data[:32], (bytes32));

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                     DEPOSIT DISPATCH                       */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == Deposit.selector && _identifier.chainId != block.chainid) {
            (, address asset, uint256 amount, address onBehalfOf,, uint256 mintMode, uint256 amountScaled) =
                abi.decode(_data[64:], (address, address, uint256, address, uint16, uint256, uint256));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            IRToken(reserve.rTokenAddress).updateCrossChainBalance(onBehalfOf, amountScaled, mintMode);
            lendingPool.updateStates(asset, amount, 0, UPDATE_RATES_AND_STATES_MASK);
        }
        if (selector == CrossChainDeposit.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (address sender, address asset, uint256 amount, address onBehalfOf, uint16 referralCode) =
                abi.decode(_data[96:], (address, address, uint256, address, uint16));
            lendingPool.deposit(sender, asset, amount, onBehalfOf, referralCode);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    WITHDRAW DISPATCH                       */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


        if (selector == Withdraw.selector && _identifier.chainId != block.chainid) {
            (, address asset, address to, uint256 amount, uint256 mintMode, uint256 amountScaled) =
                abi.decode(_data[64:], (address, address, address, uint256, uint256, uint256));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            IRToken(reserve.rTokenAddress).updateCrossChainBalance(to, amountScaled, mintMode);
            lendingPool.updateStates(asset, 0, amount, UPDATE_RATES_AND_STATES_MASK);
        }
        if (selector == CrossChainWithdraw.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (address sender, address asset, uint256 amount, address to, uint256 toChainId) =
                abi.decode(_data[96:], (address, address, uint256, address, uint256));
            lendingPool.withdraw(sender, asset, amount, to, toChainId);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    BORROW DISPATCH                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


        if (selector == Borrow.selector && _identifier.chainId != block.chainid) {
            (address asset, uint256 amount,, address onBehalfOf,,, uint256 mintMode, uint256 amountScaled,) =
                abi.decode(_data[32:], (address, uint256, address, address, uint256, uint256, uint256, uint256, uint16));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            IVariableDebtToken(reserve.variableDebtTokenAddress).updateCrossChainBalance(
                onBehalfOf, amountScaled, mintMode
            );

            lendingPool.updateStates(asset, 0, amount, UPDATE_RATES_AND_STATES_MASK);
        }
        if (selector == CrossChainBorrow.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (
                uint256 sendToChainId,
                address sender,
                address asset,
                uint256 amount,
                address onBehalfOf,
                uint16 referralCode
            ) = abi.decode(_data[96:], (uint256, address, address, uint256, address, uint16));
            lendingPool.borrow(sender, asset, amount, onBehalfOf, sendToChainId, referralCode);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    REPAY DISPATCH                          */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == Repay.selector && _identifier.chainId != block.chainid) {
            (address asset, uint256 amount,, address repayer,, uint256 mintMode, uint256 amountBurned) =
                abi.decode(_data[32:], (address, uint256, address, address, uint256, uint256, uint256));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            IVariableDebtToken(reserve.variableDebtTokenAddress).updateCrossChainBalance(
                repayer, amountBurned, mintMode
            );
            lendingPool.updateStates(asset, amount, 0, UPDATE_RATES_AND_STATES_MASK);
        } else if (selector == CrossChainRepay.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (address sender, address asset, uint256 amount, address onBehalfOf, uint256 debtChainId) =
                abi.decode(_data[64:], (address, address, uint256, address, uint256));

            address rVaultAsset = lendingPool.getRVaultAssetOrRevert(asset);
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(rVaultAsset);

            IERC20(asset).safeTransferFrom(sender, address(this), amount);
            if (pool_type == 1) {
                IERC20(asset).approve(reserve.superAsset, amount);
                ISuperAsset(reserve.superAsset).deposit(rVaultAsset, amount);
            } else {
                IERC20(asset).safeTransfer(rVaultAsset, amount);
            }
            // send rvaultasset to debtchain  normal bridging
            // bridge rVaultasset and not the underlying remember ...
            // @audit check
            // @audit check
            IRVaultAsset(rVaultAsset).bridge(address(lendingPool), debtChainId, amount);
            emit CrossChainRepayFinalize(debtChainId, sender, onBehalfOf, amount, rVaultAsset);
        } else if (selector == CrossChainRepayFinalize.selector && abi.decode(_data[32:64], (uint256)) == block.chainid)
        {
            (address sender, address onBehalfOf, uint256 amount, address asset) =
                abi.decode(_data[64:], (address, address, uint256, address));
            lendingPool.repay(sender, onBehalfOf, asset, amount);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    LIQUIDATION CALL DISPATCH               */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        if (selector == ILendingPoolCollateralManager.LiquidationCall.selector && _identifier.chainId != block.chainid)
        {
            (
                address collateralAsset,
                address debtAsset,
                address user,
                uint256 actualDebtToLiquidate,
                uint256 maxCollateralToLiquidate,
                , //liquidator
                bool receiveRToken,
                uint256 variableDebtBurned,
                uint256 collateralRTokenBurned
            ) = abi.decode(_data[32:], (address, address, address, uint256, uint256, address, bool, uint256, uint256));

            DataTypes.ReserveData memory debtReserve = lendingPool.getReserveData(debtAsset);
            IVariableDebtToken(debtReserve.variableDebtTokenAddress).updateCrossChainBalance(
                user, variableDebtBurned, 2
            );
            lendingPool.updateStates(debtAsset, 0, actualDebtToLiquidate, UPDATE_RATES_AND_STATES_MASK);
            if (!receiveRToken) {
                DataTypes.ReserveData memory collateralReserve = lendingPool.getReserveData(collateralAsset);
                IRToken(collateralReserve.rTokenAddress).updateCrossChainBalance(user, collateralRTokenBurned, 2);
                lendingPool.updateStates(collateralAsset, 0, maxCollateralToLiquidate, UPDATE_RATES_AND_STATES_MASK);
            }
        }
        if (selector == CrossChainLiquidationCall.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (
                address sender,
                address collateralAsset,
                address debtAsset,
                address user,
                uint256 debtToCover,
                bool receiveRToken
            ) = abi.decode(_data[64:], (address, address, address, address, uint256, bool));
            lendingPool.liquidationCall(
                sender, collateralAsset, debtAsset, user, debtToCover, receiveRToken, block.chainid
            );
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    FLASHLOAN DISPATCH                      */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (
            selector == FlashLoan.selector && abi.decode(_data[32:64], (uint256)) != block.chainid
                && abi.decode(_data[64:96], (bool))
        ) {
            (, address asset, uint256 amount) = abi.decode(_data[96:160], (address, address, uint256));
            lendingPool.updateStates(asset, 0, amount, UPDATE_RATES_AND_STATES_MASK);
        }
        if (selector == CrossChainInitiateFlashloan.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (
                address sender,
                address receiverAddress,
                address[] memory assets,
                uint256[] memory amounts,
                uint256[] memory modes,
                address onBehalfOf,
                bytes memory params,
                uint16 referralCode
            ) = abi.decode(_data[96:], (address, address, address[], uint256[], uint256[], address, bytes, uint16));
            lendingPool.flashLoan(sender, receiverAddress, assets, amounts, modes, onBehalfOf, params, referralCode);
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
            emit CrossChainDeposit(chainIds[i], msg.sender, asset, amounts[i], onBehalfOf, referralCode);
        }
    }

    // TODO: supercontracts.eth frontend would need to calculate how much to burn for the rTokens on each chain for withdraw.
    // toChainId - check if deposits are here and withdraw them all ...
    // intercluster like if the toChainId withdraw is in opsuperchain then withdraw from superchain first and then go crosscluster ...
    // TODO: @superForgerer in testing withdraw keep a track of deposits in what chains they are and use the same logic as frontend
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
            emit CrossChainWithdraw(chainIds[i], msg.sender, asset, amounts[i], to, toChainId);
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
            emit CrossChainBorrow(chainIds[i], sendToChainId, msg.sender, asset, amounts[i], onBehalfOf, referralCode);
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
        onlyRelayer
    {
        for (uint256 i = 0; i < _repayParams.length; i++) {
            emit CrossChainRepay(
                _repayParams[i].fundChainId,
                msg.sender,
                _asset,
                _repayParams[i].amount,
                _onBehalfOf,
                _repayParams[i].debtChainId
            );
        }
    }

    /**
     * @dev Allows depositors to enable/disable a specific deposited asset as collateral across multiple chains
     * @param asset The address of the underlying asset deposited
     * @param useAsCollateral `true` if the user wants to use the deposit as collateral, `false` otherwise
     * @param chainIds Array of chain IDs where the collateral setting should be updated
     */
    function setUserUseReserveAsCollateral(address asset, bool[] calldata useAsCollateral, uint256[] calldata chainIds)
        external
        whenNotPaused
    {
        for (uint256 i = 0; i < chainIds.length; i++) {
            emit SetUserUseReserveAsCollateralCrossChain(chainIds[i], msg.sender, asset, useAsCollateral[i]);
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
            emit CrossChainLiquidationCall(
                chainIds[i], msg.sender, collateralAsset, debtAsset, user, debtToCover[i], receiveRToken
            );
        }
    }

    function initiateFlashLoan(
        uint256[] calldata chainIds,
        address receiverAddress,
        address[][] calldata assets,
        uint256[][] calldata amounts,
        uint256[][] calldata modes,
        address onBehalfOf,
        bytes[] calldata params,
        uint16[] calldata referralCode
    ) external whenNotPaused {
        for (uint256 i = 0; i < chainIds.length; i++) {
            emit CrossChainInitiateFlashloan(
                chainIds[i],
                msg.sender,
                receiverAddress,
                assets[i],
                amounts[i],
                modes[i],
                onBehalfOf,
                params[i],
                referralCode[i]
            );
        }
    }

    /**
     * @dev Set the _pause state of a reserve
     * - Only callable by the LendingPoolConfigurator contract
     * @param val `true` to pause the reserve, `false` to un-pause it
     */
    function setPause(bool val) external onlyLendingPoolConfigurator {
        if (val) {
            _pause();
        } else {
            _unpause();
        }
    }
}
