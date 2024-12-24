// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Initializable} from "@solady/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import "./interfaces/ILendingPool.sol";
import "@contracts-bedrock/L2/interfaces/ICrossL2Inbox.sol";
import {ISuperchainAsset} from "./interfaces/ISuperchainAsset.sol";
import {IAToken} from "./interfaces/IAToken.sol";
import {IStableDebtToken} from "./interfaces/IStableDebtToken.sol";
import {IVariableDebtToken} from "./interfaces/IVariableDebtToken.sol";
import {ISuperchainTokenBridge} from "@contracts-bedrock/L2/interfaces/ISuperchainTokenBridge.sol";

import {ReserveLogic} from "./libraries/logic/ReserveLogic.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {SuperPausable} from "@interop-std/utils/SuperPausable.sol";
import {Predeploys} from "@contracts-bedrock/libraries/Predeploys.sol";

contract Router is Initializable, SuperPausable {
    using SafeERC20 for IERC20;
    using ReserveLogic for DataTypes.ReserveData;

    uint256 public constant ROUTER_REVISION = 0x1;
    ILendingPool public lendingPool;
    ILendingPoolAddressesProvider public addressesProvider;
    address public relayer;

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

    /**
     * @dev Function is invoked by the proxy contract to initialize the Router contract
     * @param _lendingPool The address of the LendingPool contract
     * @param _addressesProvider The address of the LendingPoolAddressesProvider contract
     */
    function initialize(address _lendingPool, address _addressesProvider) public initializer {
        lendingPool = ILendingPool(_lendingPool);
        addressesProvider = ILendingPoolAddressesProvider(_addressesProvider);
    }

    function dispatch(Identifier calldata _identifier, bytes calldata _data) external onlyRelayer whenNotPaused {
        if (_identifier.origin != address(this)) revert OriginNotSuperLend();
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_identifier, keccak256(_data));
        
        bytes32 selector = abi.decode(_data[:32], (bytes32));

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                     DEPOSIT DISPATCH                       */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == Deposit.selector && _identifier.chainId != block.chainid) {
            (address asset, uint256 amount,,, uint256 mintMode, uint256 amountScaled) =
                abi.decode(_data[64:], (address, uint256, address, uint16, uint256, uint256));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            IAToken(reserve.aTokenAddress).updateCrossChainBalance(amountScaled, mintMode);
            lendingPool.updateStates(asset, amount, 0, bytes2(uint16(3)));
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
            (address asset,, uint256 amount, uint256 mode, uint256 amountScaled) =
                abi.decode(_data[64:], (address, address, uint256, uint256, uint256));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            IAToken(reserve.aTokenAddress).updateCrossChainBalance(amountScaled, mode);
            lendingPool.updateStates(asset, 0, amount, bytes2(uint16(3)));
        }
        if (selector == CrossChainWithdraw.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (address sender, address asset, uint256 amount, address to) =
                abi.decode(_data[96:], (address, address, uint256, address));
            lendingPool.withdraw(sender, asset, amount, to, _identifier.chainId);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    BORROW DISPATCH                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == Borrow.selector && _identifier.chainId != block.chainid) {
            (address asset, uint256 amount,,, uint256 interestRateMode,,,, uint256 amountScaled,) = abi.decode(
                _data[32:], (address, uint256, address, address, uint256, uint256, uint256, uint256, uint256, uint16)
            );
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            if (interestRateMode == 1) {
                IStableDebtToken(reserve.stableDebtTokenAddress).updateCrossChainBalance(amountScaled, 1);
            } else if (interestRateMode == 2) {
                IVariableDebtToken(reserve.variableDebtTokenAddress).updateCrossChainBalance(amountScaled, 1);
            }
            lendingPool.updateStates(asset, 0, amount, bytes2(uint16(3)));
        }
        if (selector == CrossChainBorrow.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (
                uint256 sendToChainId,
                address sender,
                address asset,
                uint256 amount,
                uint256 interestRateMode,
                address onBehalfOf,
                uint16 referralCode
            ) = abi.decode(_data[96:], (uint256, address, address, uint256, uint256, address, uint16));
            lendingPool.borrow(sender, asset, amount, interestRateMode, onBehalfOf, sendToChainId, referralCode);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    REPAY DISPATCH                          */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == Repay.selector && _identifier.chainId != block.chainid) {
            (address asset, uint256 amount,,, uint256 rateMode, uint256 mode, uint256 amountBurned) =
                abi.decode(_data[32:], (address, uint256, address, address, uint256, uint256, uint256));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            if (rateMode == 1) {
                IStableDebtToken(reserve.stableDebtTokenAddress).updateCrossChainBalance(amountBurned, mode);
            } else if (rateMode == 2) {
                IVariableDebtToken(reserve.variableDebtTokenAddress).updateCrossChainBalance(amountBurned, mode);
            }
            lendingPool.updateStates(asset, amount, 0, bytes2(uint16(3)));
        }
        if (selector == CrossChainRepay.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (address sender, address asset, uint256 amount, uint256 rateMode, address onBehalfOf) =
                abi.decode(_data[64:], (address, address, uint256, uint256, address));
            lendingPool.repay(sender, asset, amount, rateMode, onBehalfOf);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    LIQUIDATION CALL DISPATCH               */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == LiquidationCall.selector && _identifier.chainId != block.chainid) {
            (
                address collateralAsset,
                address debtAsset,
                ,
                uint256 actualDebtToLiquidate,
                uint256 maxCollateralToLiquidate,
                ,
                bool receiveAToken,
                uint256 stableDebtBurned,
                uint256 variableDebtBurned,
                uint256 collateralATokenBurned
            ) = abi.decode(
                _data[64:], (address, address, address, uint256, uint256, address, bool, uint256, uint256, uint256)
            );
            DataTypes.ReserveData memory debtReserve = lendingPool.getReserveData(debtAsset);
            IVariableDebtToken(debtReserve.variableDebtTokenAddress).updateCrossChainBalance(variableDebtBurned, 2);
            IStableDebtToken(debtReserve.stableDebtTokenAddress).updateCrossChainBalance(stableDebtBurned, 2);
            lendingPool.updateStates(debtAsset, 0, actualDebtToLiquidate, bytes2(uint16(3)));
            if (!receiveAToken) {
                DataTypes.ReserveData memory collateralReserve = lendingPool.getReserveData(collateralAsset);
                IAToken(collateralReserve.aTokenAddress).updateCrossChainBalance(collateralATokenBurned, 2);
                lendingPool.updateStates(collateralAsset, 0, maxCollateralToLiquidate, bytes2(uint16(3)));
            }
        }
        if (selector == CrossChainLiquidationCall.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (
                address sender,
                address collateralAsset,
                address debtAsset,
                address user,
                uint256 debtToCover,
                bool receiveAToken,
                uint256 sendToChainId
            ) = abi.decode(_data[64:], (address, address, address, address, uint256, bool, uint256));
            lendingPool.liquidationCall(
                sender, collateralAsset, debtAsset, user, debtToCover, receiveAToken, sendToChainId
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
            lendingPool.updateStates(asset, 0, amount, bytes2(uint16(3)));
        }
        if (selector == InitiateFlashLoanCrossChain.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
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

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                    REBALANCE DISPATCH                      */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == RebalanceStableBorrowRate.selector && _identifier.chainId != block.chainid) {
            (address asset,, uint256 amountBurned, uint256 amountMinted) =
                abi.decode(_data[32:], (address, address, uint256, uint256));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            IStableDebtToken(reserve.stableDebtTokenAddress).updateCrossChainBalance(amountBurned, 2);
            IStableDebtToken(reserve.stableDebtTokenAddress).updateCrossChainBalance(amountMinted, 1);
            lendingPool.updateStates(asset, 0, 0, bytes2(uint16(3)));
        }
        if (
            selector == CrossChainRebalanceStableBorrowRate.selector
                && abi.decode(_data[32:64], (uint256)) == block.chainid
        ) {
            (address asset, address user) = abi.decode(_data[64:], (address, address));
            lendingPool.rebalanceStableBorrowRate(asset, user);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*               UseReserveAsCollateral DISPATCH              */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (
            selector == CrossChainSetUserUseReserveAsCollateral.selector
                && abi.decode(_data[32:64], (uint256)) == block.chainid
        ) {
            (address sender, address asset, bool useAsCollateral) = abi.decode(_data[64:], (address, address, bool));
            lendingPool.setUserUseReserveAsCollateral(sender, asset, useAsCollateral);
        }

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*               SWAP DISPATCH                                */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        if (selector == Swap.selector && _identifier.chainId != block.chainid) {
            (, address asset, uint256 rateMode, uint256 variableDebtAmount, uint256 stableDebtAmount) =
                abi.decode(_data[32:], (address, address, uint256, uint256, uint256));
            DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
            if (rateMode == 2) {
                IStableDebtToken(reserve.stableDebtTokenAddress).updateCrossChainBalance(stableDebtAmount, 2);
                IVariableDebtToken(reserve.variableDebtTokenAddress).updateCrossChainBalance(variableDebtAmount, 1);
            } else if (rateMode == 1) {
                IVariableDebtToken(reserve.variableDebtTokenAddress).updateCrossChainBalance(variableDebtAmount, 2);
                IStableDebtToken(reserve.stableDebtTokenAddress).updateCrossChainBalance(stableDebtAmount, 1);
            }
            lendingPool.updateStates(asset, 0, 0, bytes2(uint16(3)));
        }
        if (selector == CrossChainSwapBorrowRateMode.selector && abi.decode(_data[32:64], (uint256)) == block.chainid) {
            (address sender, address asset, uint256 rateMode) = abi.decode(_data[64:], (address, address, uint256));
            lendingPool.swapBorrowRateMode(sender, asset, rateMode);
        }

        revert InvalidSelector(selector);
    }

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve across multiple chains
     * @param asset The address of the underlying asset to deposit
     * @param amounts Array of amounts to deposit per chain
     * @param onBehalfOf Address that will receive the aTokens
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

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
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

    /**
     * @dev Allows users to borrow across multiple chains, provided they have enough collateral
     * @param asset The address of the underlying asset to borrow
     * @param amounts Array of amounts to borrow per chain
     * @param interestRateMode The interest rate mode: 1 for Stable, 2 for Variable
     * @param referralCode Code used to register the integrator originating the operation
     * @param onBehalfOf Address that will receive the debt
     * @param chainIds Array of chain IDs where to borrow from
     */
    function borrow(
        address asset,
        uint256[] calldata amounts,
        uint256[] calldata interestRateMode,
        uint16 referralCode,
        address onBehalfOf,
        uint256 sendToChainId,
        uint256[] calldata chainIds
    ) external whenNotPaused {
        for (uint256 i = 0; i < chainIds.length; i++) {
            emit CrossChainBorrow(
                chainIds[i],
                sendToChainId,
                msg.sender,
                asset,
                amounts[i],
                interestRateMode[i],
                onBehalfOf,
                referralCode
            );
        }
    }

    /**
     * @dev Repays a borrowed `amount` on a specific reserve across multiple chains, burning the equivalent debt tokens owned
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param amounts Array of amounts to repay per chain
     * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
     * @param rateMode Array of interest rate modes to repay per chain: 1 for Stable, 2 for Variable
     * @param onBehalfOf Address of the user who will get their debt reduced/removed
     * @param chainIds Array of chain IDs where the debt needs to be repaid
     */
    function repay(
        address asset,
        uint256[] calldata amounts,
        uint256 totalAmount,
        uint256[] calldata rateMode,
        address onBehalfOf,
        uint256[] calldata chainIds
    ) external whenNotPaused {
        DataTypes.ReserveData memory reserve = lendingPool.getReserveData(asset);
        IERC20(asset).safeTransferFrom(msg.sender, address(this), totalAmount);
        ISuperchainAsset(reserve.superchainAssetAddress).mint(address(this), totalAmount);
        for (uint256 i = 1; i < chainIds.length; i++) {
            if (chainIds[i] != block.chainid) {
ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE).sendERC20(
                    reserve.superchainAssetAddress, address(this), amounts[i], chainIds[i]
                );
            }
            emit CrossChainRepay(chainIds[i], msg.sender, asset, amounts[i], rateMode[i], onBehalfOf);
        }
    }

    function crossChainSwapBorrowRateMode(address asset, uint256 rateMode, uint256[] calldata chainIds)
        external
        whenNotPaused
    {
        for (uint256 i = 0; i < chainIds.length; i++) {
            emit CrossChainSwapBorrowRateMode(chainIds[i], msg.sender, asset, rateMode);
        }
    }

    /**
     * @dev Rebalances the stable interest rate of a user to the current stable rate defined on the reserve.
     * - Users can be rebalanced if the following conditions are satisfied:
     *     1. Usage ratio is above 95%
     *     2. the current deposit APY is below REBALANCE_UP_THRESHOLD * maxVariableBorrowRate, which means that too much has been
     *        borrowed at a stable rate and depositors are not earning enough
     * @param asset The address of the underlying asset borrowed
     * @param chainIds Array of chain IDs where the rebalance should be executed
     *
     */
    function rebalanceStableBorrowRate(address asset, uint256[] calldata chainIds) external whenNotPaused {
        for (uint256 i = 0; i < chainIds.length; i++) {
            emit RebalanceStableBorrowRateCrossChain(chainIds[i], asset, msg.sender);
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
     * @param totalDebtToCover The total debt amount of borrowed `asset` the liquidator wants to cover
     * @param chainIds Array of chain IDs where the liquidation should be executed
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * @param sendToChainId the chain id to send the collateral to if receiveAToken is `false`
     * to receive the underlying collateral asset directly
     *
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256[] calldata debtToCover,
        uint256 totalDebtToCover,
        uint256[] calldata chainIds,
        bool receiveAToken,
        uint256 sendToChainId
    ) external whenNotPaused {
        DataTypes.ReserveData memory reserve = lendingPool.getReserveData(debtAsset);
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), totalDebtToCover);
        ISuperchainAsset(reserve.superchainAssetAddress).mint(address(this), totalDebtToCover);
        for (uint256 i = 0; i < chainIds.length; i++) {
            if (chainIds[i] != block.chainid) {
                ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE).sendERC20(
                    reserve.superchainAssetAddress, address(this), debtToCover[i], chainIds[i]
                );
            }
            emit CrossChainLiquidationCall(
                chainIds[i],
                msg.sender,
                collateralAsset,
                debtAsset,
                user,
                debtToCover[i],
                receiveAToken,
                sendToChainId
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
            emit InitiateFlashLoanCrossChain(
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
     * @dev Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     *
     */

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
