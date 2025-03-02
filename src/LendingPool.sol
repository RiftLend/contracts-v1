// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {IRToken} from "./interfaces/IRToken.sol";
import {IVariableDebtToken} from "./interfaces/IVariableDebtToken.sol";
import {IFlashLoanReceiver} from "./interfaces/IFlashLoanReceiver.sol";
import {IPriceOracleGetter} from "./interfaces/IPriceOracleGetter.sol";
import "./interfaces/ILendingPool.sol";
import {ISuperAsset} from "./interfaces/ISuperAsset.sol";
import {IRVaultAsset} from "./interfaces/IRVaultAsset.sol";
import {ILendingPoolCollateralManager} from "src/interfaces/ILendingPoolCollateralManager.sol";

import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {Helpers} from "./libraries/helpers/Helpers.sol";
import {WadRayMath} from "./libraries/math/WadRayMath.sol";
import {PercentageMath} from "./libraries/math/PercentageMath.sol";
import {ReserveLogic} from "./libraries/logic/ReserveLogic.sol";
import {GenericLogic} from "./libraries/logic/GenericLogic.sol";
import {ValidationLogic} from "./libraries/logic/ValidationLogic.sol";
import {ReserveConfiguration} from "./libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "./libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {LendingPoolStorage} from "./LendingPoolStorage.sol";
import {Predeploys} from "./libraries/Predeploys.sol";
import {SuperPausable} from "./interop-std/src/utils/SuperPausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LendingPool is Initializable, LendingPoolStorage, SuperPausable {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;

    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    bytes2 private constant UPDATE_STATE_MASK = bytes2(uint16(1));
    bytes2 private constant UPDATE_RATES_MASK = bytes2(uint16(2));
    bytes2 private constant UPDATE_RATES_AND_STATES_MASK = bytes2(uint16(3));
    uint256 private constant LENDINGPOOL_REVISION = 0x1;
    uint256 public constant _flashLoanPremiumTotal = 9;
    uint256 public constant _maxNumberOfReserves = 128;

    error LP_LIQUIDATION_CALL_FAILED();
    error LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR();
    error ONLY_ROUTER_CALL();
    error ONLY_ROUTER_OR_SELF_CALL();
    error LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN();
    error LP_CALLER_MUST_BE_AN_RTOKEN();
    error LP_NOT_CONTRACT();
    error LP_NO_MORE_RESERVES_ALLOWED();
    error RVAULT_NOT_FOUND_FOR_ASSET();
    error LP_RESERVE_NOT_FOUND();

    event logAddresses(address[] addresses);
    event RVaultAssetUpdated(address asset, address rVaultAsset);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Modifiers                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function onlyLendingPoolConfigurator() internal view {
        if (_addressesProvider.getLendingPoolConfigurator() != msg.sender) {
            revert LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR();
        }
    }

    function onlyRouter() internal view {
        if (_addressesProvider.getRouter() != msg.sender) revert ONLY_ROUTER_CALL();
    }

    function onlyRouterOrSelf() internal view {
        if (!(_addressesProvider.getRouter() == msg.sender || msg.sender == address(this))) {
            revert ONLY_ROUTER_OR_SELF_CALL();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Initializer                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Function is invoked by the proxy contract when the LendingPool contract is added to the
     * LendingPoolAddressesProvider of the market.
     * - Caching the address of the LendingPoolAddressesProvider in order to reduce gas consumption
     *   on subsequent operations
     * @param provider The address of the LendingPoolAddressesProvider
     *
     */
    function initialize(ILendingPoolAddressesProvider provider) external initializer {
        _addressesProvider = provider;
        pool_type = provider.getPoolType();
    }

    /**
     * @notice Deposits a specified `amount` of `asset` into the lending pool on behalf of `onBehalfOf`.
     * @dev This function can only be called by the router.
     * @param sender The address of the sender initiating the deposit.
     * @param asset The address of the asset to be deposited (underlying, superAsset, or Rvault).
     * @param amount The amount of the asset to be deposited.
     * @param onBehalfOf The address on whose behalf the deposit is made.
     * @param referralCode The referral code for the deposit.
     */
    function deposit(address sender, address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        onlyRouter();
        address rVaultAsset = getRVaultAssetOrRevert(asset);
        DataTypes.ReserveData storage reserve = _reserves[rVaultAsset];
        _updateStates(reserve, rVaultAsset, amount, 0, UPDATE_RATES_AND_STATES_MASK);
        address rToken = reserve.rTokenAddress;
        ValidationLogic.validateDeposit(reserve, amount);
        IERC20(asset).safeTransferFrom(sender, address(this), amount);

        // // //If pool is on op_superchain,
        // // // wrap them into superAsset with lendingPool as receiver

        if (pool_type == 1) {
            ISuperAsset(reserve.superAsset).deposit(address(this), amount);
        }
        IRVaultAsset(rVaultAsset).mint(amount, rToken);
        // We now mint RTokens to the user as a receipt of their deposit
        (bool isFirstDeposit, uint256 mintMode, uint256 amountScaled) =
            IRToken(rToken).mint(onBehalfOf, amount, reserve.liquidityIndex);

        if (isFirstDeposit) {
            unchecked {
                _usersConfig[onBehalfOf].setUsingAsCollateral(reserve.id, true);
            }
            emit ILendingPool.ReserveUsedAsCollateralEnabled(rVaultAsset, onBehalfOf);
        }

        emit ILendingPool.Deposit(
            DataTypes.DepositEventParams(sender, rVaultAsset, amount, onBehalfOf, referralCode, mintMode, amountScaled)
        );
    }

    function withdraw(address sender, address asset, uint256 amount, address to, uint256 toChainId) external {
        onlyRouter();

        address rVaultAsset = getRVaultAssetOrRevert(asset);
        DataTypes.ReserveData storage reserve = _reserves[rVaultAsset];
        address rToken = reserve.rTokenAddress;
        uint256 userBalance = IRToken(rToken).balanceOf(sender);
        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;
        DataTypes.UserConfigurationMap storage senderConfig = _usersConfig[sender];

        ValidationLogic.validateWithdraw(
            rVaultAsset,
            sender,
            userBalance,
            senderConfig,
            amountToWithdraw,
            _reservesCount,
            _addressesProvider.getPriceOracle(),
            address(this)
        );

        _updateStates(reserve, rVaultAsset, 0, amountToWithdraw, UPDATE_RATES_AND_STATES_MASK);

        if (amountToWithdraw == userBalance) {
            _usersConfig[sender].setUsingAsCollateral(reserve.id, false);
            emit ILendingPool.ReserveUsedAsCollateralDisabled(rVaultAsset, sender);
        }

        (uint256 mode, uint256 amountScaled) =
            IRToken(rToken).burn(sender, to, toChainId, amountToWithdraw, reserve.liquidityIndex);

        emit ILendingPool.Withdraw(
            DataTypes.WithdrawEventParams(sender, rVaultAsset, to, amountToWithdraw, mode, amountScaled)
        );
    }

    function borrow(
        address sender,
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint256 sendToChainId,
        uint16 referralCode
    ) external {
        onlyRouter();

        address rVaultAsset = getRVaultAssetOrRevert(asset);

        address rToken = _reserves[rVaultAsset].rTokenAddress;

        _executeBorrow(
            DataTypes.ExecuteBorrowParams(
                asset, sender, onBehalfOf, sendToChainId, amount, rVaultAsset, rToken, referralCode, true
            )
        );
    }

    function repay(address sender, address onBehalfOf, address asset, uint256 amount) external {
        onlyRouter();

        address rVaultAsset = getRVaultAssetOrRevert(asset);
        DataTypes.ReserveData storage reserve = _reserves[rVaultAsset];
        uint256 debt = Helpers.getUserCurrentDebt(onBehalfOf, reserve);
        ValidationLogic.validateRepay(reserve, amount, debt);

        uint256 paybackAmount;
        if (amount <= debt) {
            paybackAmount = amount;
        } else {
            paybackAmount = debt;
            IERC20(asset).safeTransfer(sender, amount - paybackAmount);
        }
        _updateStates(reserve, asset, paybackAmount, 0, UPDATE_RATES_AND_STATES_MASK);
        (uint256 mode, uint256 amountBurned) = IVariableDebtToken(reserve.variableDebtTokenAddress).burn(
            onBehalfOf, paybackAmount, reserve.variableBorrowIndex
        );

        address rToken = reserve.rTokenAddress;
        if (debt - paybackAmount == 0) {
            _usersConfig[onBehalfOf].setBorrowing(reserve.id, false);
        }

        if (pool_type == 1) ISuperAsset(reserve.superAsset).deposit(address(address(this)), paybackAmount);
        IRVaultAsset(rVaultAsset).deposit(paybackAmount, rToken);
        IRToken(rToken).handleRepayment(onBehalfOf, paybackAmount);

        emit ILendingPool.Repay(
            DataTypes.RepayEventParams(asset, paybackAmount, onBehalfOf, sender, mode, amountBurned)
        );
    }

    function liquidationCall(DataTypes.CrosschainLiquidationCallData calldata liquidationParams) external {
        onlyRouter();
        address collateralManager = _addressesProvider.getLendingPoolCollateralManager();

        // Getting liquidation debt amount in rVaultAsset
        address rVaultDebtAsset = getRVaultAssetOrRevert(liquidationParams.debtAsset);
        address rVaultCollateralAsset = getRVaultAssetOrRevert(liquidationParams.collateralAsset);
        DataTypes.ReserveData storage reserve = _reserves[rVaultDebtAsset];
        IERC20(liquidationParams.debtAsset).safeTransferFrom(
            liquidationParams.sender, address(this), liquidationParams.debtToCover
        );
        if (pool_type == 1) ISuperAsset(reserve.superAsset).deposit(address(this), liquidationParams.debtToCover);

        IRVaultAsset(rVaultDebtAsset).mint(liquidationParams.debtToCover, address(this));

        //solium-disable-next-lines
        (bool success,) = collateralManager.delegatecall(
            abi.encodeWithSelector(
                ILendingPoolCollateralManager.liquidationCall.selector,
                DataTypes.CrosschainLiquidationCallData(
                    block.chainid,
                    liquidationParams.sender,
                    rVaultCollateralAsset,
                    rVaultDebtAsset,
                    liquidationParams.user,
                    liquidationParams.debtToCover,
                    liquidationParams.receiveRToken
                )
            )
        );

        if (!success) revert LP_LIQUIDATION_CALL_FAILED();
    }

    /**
     * @dev Allows smartcontracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.
     * For further details please visit https://developers.aave.com
     * @param sender The address of the sender
     * @param receiverAddress The address of the contract receiving the funds, implementing the IFlashLoanReceiver interface
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts amounts being flash-borrowed
     * @param modes Types of the debt to open if the flash loan is not returned:
     *   0 -> Don't open any debt, just revert if funds can't be transferred from the receiver
     *   1 -> Open debt at stable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     *   2 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     * @param onBehalfOf The address  that will receive the debt in the case of using on `modes` 1 or 2
     * @param params Variadic packed params to pass to the receiver as extra information
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     *
     */
    function flashLoan(
        address sender,
        address receiverAddress,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory modes,
        address onBehalfOf,
        bytes memory params,
        uint16 referralCode
    ) external {
        onlyRouter();

        DataTypes.FlashLoanLocalVars memory vars;

        ValidationLogic.validateFlashloan(modes, assets, amounts);

        address[] memory rTokenAddresses = new address[](assets.length);
        uint256[] memory premiums = new uint256[](assets.length);

        vars.receiver = IFlashLoanReceiver(receiverAddress);

        for (vars.i = 0; vars.i < assets.length; vars.i++) {
            address rVaultAsset = getRVaultAssetOrRevert(assets[vars.i]);

            rTokenAddresses[vars.i] = _reserves[rVaultAsset].rTokenAddress;

            premiums[vars.i] = (amounts[vars.i] * _flashLoanPremiumTotal) / 10000;

            IRToken(rTokenAddresses[vars.i]).transferUnderlyingTo(receiverAddress, amounts[vars.i], block.chainid);
        }

        if (!vars.receiver.executeOperation(assets, amounts, premiums, sender, params)) {
            revert LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN();
        }

        bool borrowExecuted = false;
        for (vars.i = 0; vars.i < assets.length; vars.i++) {
            vars.currentAsset = getRVaultAssetOrRevert(assets[vars.i]);
            vars.currentAmount = amounts[vars.i];
            vars.currentPremium = premiums[vars.i];
            vars.currentrTokenAddress = rTokenAddresses[vars.i];
            vars.currentAmountPlusPremium = vars.currentAmount + vars.currentPremium;

            if (DataTypes.InterestRateMode(modes[vars.i]) == DataTypes.InterestRateMode.NONE) {
                _reserves[vars.currentAsset].updateState();
                _reserves[vars.currentAsset].cumulateToLiquidityIndex(
                    IERC20(vars.currentrTokenAddress).totalSupply(), vars.currentPremium
                );
                _reserves[vars.currentAsset].updateInterestRates(
                    vars.currentAsset, vars.currentrTokenAddress, vars.currentAmountPlusPremium, 0
                );

                IERC20(assets[vars.i]).safeTransferFrom(receiverAddress, address(this), vars.currentAmountPlusPremium);
                IERC20(assets[vars.i]).approve(vars.currentAsset, vars.currentAmountPlusPremium);

                address underlying = IRVaultAsset(vars.currentAsset).asset();

                if (underlying != assets[vars.i] && pool_type == 1) {
                    ISuperAsset(underlying).deposit(address(this), vars.currentAmountPlusPremium);
                    IERC20(underlying).approve(vars.currentAsset, vars.currentAmountPlusPremium);
                }

                IRVaultAsset(vars.currentAsset).mint(vars.currentAmountPlusPremium, vars.currentrTokenAddress);
            } else {
                // If the user chose to not return the funds, the system checks if there is enough collateral and
                // eventually opens a debt position
                _executeBorrow(
                    DataTypes.ExecuteBorrowParams(
                        assets[vars.i],
                        sender,
                        onBehalfOf,
                        block.chainid,
                        vars.currentAmount,
                        vars.currentAsset,
                        vars.currentrTokenAddress,
                        referralCode,
                        false
                    )
                );
                borrowExecuted = true;
            }
            emit ILendingPool.FlashLoan(
                DataTypes.FlashLoanEventParams(
                    block.chainid,
                    borrowExecuted,
                    sender,
                    vars.currentAsset,
                    vars.currentAmount,
                    vars.currentPremium,
                    receiverAddress,
                    referralCode
                )
            );
        }
    }

    function updateStates(address asset, uint256 depositAmount, uint256 withdrawAmount, bytes2 mask) public {
        onlyRouterOrSelf();
        DataTypes.ReserveData storage reserve = _reserves[asset];
        _updateStates(reserve, asset, depositAmount, withdrawAmount, mask);
    }

    function _updateStates(
        DataTypes.ReserveData storage reserve,
        address asset,
        uint256 depositAmount,
        uint256 withdrawAmount,
        bytes2 mask
    ) internal {
        if (mask & UPDATE_STATE_MASK != 0) reserve.updateState();
        if (mask & UPDATE_RATES_MASK != 0) {
            reserve.updateInterestRates(asset, reserve.rTokenAddress, depositAmount, withdrawAmount);
        }
    }

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     *
     */
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        return _reserves[asset];
    }
    /**
     * @dev Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     *
     */

    function getConfiguration(address asset) external view returns (DataTypes.ReserveConfigurationMap memory) {
        return _reserves[asset].configuration;
    }

    /**
     * @dev Returns the configuration of the user across all the reserves
     * @param user The user address
     * @return The configuration of the user
     *
     */
    function getUserConfiguration(address user) external view returns (DataTypes.UserConfigurationMap memory) {
        return _usersConfig[user];
    }

    /**
     * @dev Returns the normalized income per unit of asset
     * @return The reserve's normalized income
     */
    function getReserveNormalizedIncome(address asset) external view virtual returns (uint256) {
        return _reserves[asset].getNormalizedIncome();
    }

    /**
     * @dev Returns the normalized variable debt per unit of asset
     * @return The reserve normalized variable debt
     */
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256) {
        return _reserves[asset].getNormalizedDebt();
    }

    /**
     * @dev Returns the cached LendingPoolAddressesProvider connected to this contract
     *
     */
    function getAddressesProvider() external view returns (ILendingPoolAddressesProvider) {
        return _addressesProvider;
    }

    /**
     * @dev Validates and finalizes an rToken transfer
     * - Only callable by the overlying rToken of the `asset`
     * @param asset The address of the underlying asset of the rToken
     * @param from The user from which the rTokens are transferred
     * @param to The user receiving the rTokens
     * @param amount The amount being transferred/withdrawn
     * @param balanceFromBefore The rToken balance of the `from` user before the transfer
     * @param balanceToBefore The rToken balance of the `to` user before the transfer
     */
    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external whenNotPaused {
        if (msg.sender != _reserves[asset].rTokenAddress) revert LP_CALLER_MUST_BE_AN_RTOKEN();

        ValidationLogic.validateTransfer(
            from, _usersConfig[from], _reservesCount, _addressesProvider.getPriceOracle(), address(this)
        );

        uint256 reserveId = _reserves[asset].id;

        if (from != to) {
            if (balanceFromBefore - amount == 0) {
                DataTypes.UserConfigurationMap storage fromConfig = _usersConfig[from];
                fromConfig.setUsingAsCollateral(reserveId, false);
                emit ILendingPool.ReserveUsedAsCollateralDisabled(asset, from);
            }

            if (balanceToBefore == 0 && amount != 0) {
                DataTypes.UserConfigurationMap storage toConfig = _usersConfig[to];
                toConfig.setUsingAsCollateral(reserveId, true);
                emit ILendingPool.ReserveUsedAsCollateralEnabled(asset, to);
            }
        }
    }

    /**
     * @dev Initializes a reserve, activating it, assigning an rToken and debt tokens and an
     * interest rate strategy
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param rTokenAddress The address of the rToken that will be assigned to the reserve
     * @param superAsset The address of the superAsset that will be assigned to the reserve
     * @param rTokenAddress The address of the VariableDebtToken that will be assigned to the reserve
     * @param interestRateStrategyAddress The address of the interest rate strategy contract
     *
     */
    function initReserve(
        address asset, // asset will be the rVaultAsset
        address superAsset,
        address rTokenAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external {
        onlyLendingPoolConfigurator();

        if (asset.code.length == 0) revert LP_NOT_CONTRACT();

        _reserves[asset].init(rTokenAddress, superAsset, variableDebtAddress, interestRateStrategyAddress);
        IERC20(IRVaultAsset(asset).asset()).approve(asset, type(uint256).max);
        if (pool_type == 1) {
            IERC20(ISuperAsset(superAsset).underlying()).approve(superAsset, type(uint256).max);
        }

        _addReserveToList(asset);
    }

    /**
     * @dev Updates the address of the interest rate strategy contract
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param rateStrategyAddress The address of the interest rate strategy contract
     *
     */
    function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress) external {
        onlyLendingPoolConfigurator();
        _reserves[asset].interestRateStrategyAddress = rateStrategyAddress;
    }

    /**
     * @dev Sets the address of the rVault asset for an underlying asset
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param rVaultAsset The address of the rVault asset
     *
     */
    function setRvaultAssetForUnderlying(address asset, address rVaultAsset) external {
        onlyLendingPoolConfigurator();
        _rVaultAsset[asset] = rVaultAsset;
        if (pool_type == 1) {
            address superAsset = IRVaultAsset(rVaultAsset).underlying();
            IERC20(asset).approve(superAsset, type(uint256).max);
            IERC20(superAsset).approve(rVaultAsset, type(uint256).max);
        } else {
            IERC20(asset).approve(rVaultAsset, type(uint256).max);
        }

        emit RVaultAssetUpdated(asset, rVaultAsset);
    }
    /**
     * @dev Sets the configuration bitmap of the reserve as a whole
     * - Only callable by the LendingPoolConfigurator contract
     * @param asset The address of the underlying asset of the reserve
     * @param configuration The new configuration bitmap
     *
     */

    function setConfiguration(address asset, uint256 configuration) external {
        onlyLendingPoolConfigurator();

        _reserves[asset].configuration.data = configuration;
    }

    function _executeBorrow(DataTypes.ExecuteBorrowParams memory vars) internal {
        DataTypes.ReserveData storage reserve = _reserves[vars.rVaultAsset];
        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[vars.onBehalfOf];

        address oracle = _addressesProvider.getPriceOracle();
        uint256 amountInETH = (IPriceOracleGetter(oracle).getAssetPrice(vars.asset) * vars.amount)
            / 10 ** reserve.configuration.getDecimals();

        ValidationLogic.validateBorrow(
            reserve, vars.onBehalfOf, vars.amount, amountInETH, userConfig, _reservesCount, oracle, address(this)
        );

        _updateStates(reserve, address(0), 0, 0, UPDATE_STATE_MASK);

        uint256 mintMode = 0;
        uint256 amountScaled = 0;

        bool isFirstBorrowing = false;

        (isFirstBorrowing, mintMode, amountScaled) = IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
            vars.user, vars.onBehalfOf, vars.amount, reserve.variableBorrowIndex
        );

        if (isFirstBorrowing) userConfig.setBorrowing(reserve.id, true);

        _updateStates(reserve, vars.rVaultAsset, 0, vars.releaseUnderlying ? vars.amount : 0, UPDATE_RATES_MASK);

        if (vars.releaseUnderlying) {
            IRToken(vars.rTokenAddress).transferUnderlyingTo(vars.onBehalfOf, vars.amount, vars.sendToChainId);
        }

        emit ILendingPool.Borrow(
            DataTypes.BorrowEventParams(
                vars.rVaultAsset,
                vars.amount,
                vars.user,
                vars.onBehalfOf,
                vars.sendToChainId,
                reserve.currentVariableBorrowRate,
                mintMode,
                amountScaled,
                vars.referralCode
            )
        );
    }

    function _addReserveToList(address asset) internal {
        uint256 reservesCount = _reservesCount;

        if (reservesCount >= _maxNumberOfReserves) revert LP_NO_MORE_RESERVES_ALLOWED();

        bool reserveAlreadyAdded = _reserves[asset].id != 0 || _reservesList[0] == asset;

        if (!reserveAlreadyAdded) {
            _reserves[asset].id = uint8(reservesCount);
            _reservesList[reservesCount] = asset;

            _reservesCount = reservesCount + 1;
        }
    }

    function getRVaultAssetOrRevert(address asset) public returns (address rVaultAsset) {
        rVaultAsset = _rVaultAsset[asset];
        if (rVaultAsset == address(0)) revert RVAULT_NOT_FOUND_FOR_ASSET();
    }

    function getReserveById(uint256 id) public view returns (address asset) {
        asset = _reservesList[id];
        if (asset == address(0)) revert LP_RESERVE_NOT_FOUND();
    }

    /**
     * @dev Set the _pause state of a reserve
     * - Only callable by the LendingPoolConfigurator contract
     * @param val `true` to pause the reserve, `false` to un-pause it
     */
    function setPause(bool val) external {
        onlyLendingPoolConfigurator();

        if (val) {
            _pause();
        } else {
            _unpause();
        }
    }
}
