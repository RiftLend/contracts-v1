// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";

import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IInitializableDebtToken} from "./interfaces/IInitializableDebtToken.sol";
import {IInitializableRToken} from "./interfaces/IInitializableRToken.sol";
import {IAaveIncentivesController} from "./interfaces/IAaveIncentivesController.sol";
import {ILendingPoolConfigurator} from "./interfaces/ILendingPoolConfigurator.sol";
import {ISuperAsset} from "./interfaces/ISuperAsset.sol";

import {Initializable} from "@solady/utils/Initializable.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ReserveConfiguration} from "./libraries/configuration/ReserveConfiguration.sol";
import {PercentageMath} from "./libraries/math/PercentageMath.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {LendingPool} from "./LendingPool.sol";

/**
 * @title LendingPoolConfigurator contract
 * @author Aave
 * @dev Implements the configuration methods for the Aave protocol
 * NOTE: PoolAdmin wouldn't be able to upgrade the implementation of the proxy,
 * but the proxyAdmin can.
 */
contract LendingPoolConfigurator is Initializable, ILendingPoolConfigurator {
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    ILendingPoolAddressesProvider internal addressesProvider;
    ILendingPool internal pool;
    address internal proxyAdmin;

    error CALLER_NOT_POOL_ADMIN();
    error NOT_PROXY_ADMIN_OWNER();
    error LPC_INVALID_CONFIGURATION();
    error LPC_RESERVE_LIQUIDITY_NOT_0();

    function onlyPoolAdmin() internal view {
        if (addressesProvider.getPoolAdmin() != msg.sender) revert CALLER_NOT_POOL_ADMIN();
    }

    function onlyProxyAdminOwner() internal view {
        if (ProxyAdmin(proxyAdmin).owner() != msg.sender) revert NOT_PROXY_ADMIN_OWNER();
    }

    function initialize(ILendingPoolAddressesProvider provider, address _proxyAdmin) public initializer {
        addressesProvider = provider;
        pool = ILendingPool(addressesProvider.getLendingPool());
        proxyAdmin = _proxyAdmin;
    }

    /**
     * @dev Initializes reserves in batch
     *
     */
    function batchInitReserve(InitReserveInput[] calldata input) external {
        onlyPoolAdmin();
        for (uint256 i = 0; i < input.length; i++) {
            _initReserve(input[i]);
        }
    }

    function _initReserve(InitReserveInput calldata input) internal {
        LendingPool proxyLp = LendingPool(ILendingPoolAddressesProvider(addressesProvider).getLendingPool());

        address RTokenProxyAddress = _initTokenWithProxy(
            input.rTokenImpl,
            abi.encodeWithSelector(
                IInitializableRToken.initialize.selector,
                DataTypes.RTokenInitializeParams(
                    input.treasury,
                    input.underlyingAsset,
                    IAaveIncentivesController(input.incentivesController),
                    addressesProvider,
                    input.underlyingAssetDecimals,
                    input.rTokenName,
                    input.rTokenSymbol,
                    input.params,
                    input.eventValidator
                )
            ),
            input.salt
        );

        address variableDebtTokenProxyAddress = _initTokenWithProxy(
            input.variableDebtTokenImpl,
            abi.encodeWithSelector(
                IInitializableDebtToken.initialize.selector,
                ILendingPool(address(proxyLp)),
                input.underlyingAsset,
                IAaveIncentivesController(input.incentivesController),
                addressesProvider,
                input.underlyingAssetDecimals,
                input.variableDebtTokenName,
                input.variableDebtTokenSymbol,
                input.params
            ),
            input.salt
        );

        proxyLp.initReserve(
            input.underlyingAsset,
            input.superAsset,
            RTokenProxyAddress,
            variableDebtTokenProxyAddress,
            input.interestRateStrategyAddress
        );

        DataTypes.ReserveConfigurationMap memory currentConfig = proxyLp.getConfiguration(input.underlyingAsset);

        currentConfig.setDecimals(input.underlyingAssetDecimals);

        currentConfig.setActive(true);
        currentConfig.setFrozen(false);

        proxyLp.setConfiguration(input.underlyingAsset, currentConfig.data);

        emit ReserveInitialized(
            input.underlyingAsset, RTokenProxyAddress, variableDebtTokenProxyAddress, input.interestRateStrategyAddress
        );
    }

    function withdrawSuperchainAssetSentToken(address asset, address recepient) external {
        onlyProxyAdminOwner();

        ISuperAsset(asset).withdrawTokens(asset, recepient);
    }
    /**
     * @dev Updates the RToken implementation for the reserve
     *
     */

    function updateRToken(UpdateRTokenInput calldata input) external {
        onlyProxyAdminOwner();
        DataTypes.ReserveData memory reserveData = pool.getReserveData(input.asset);

        (,,, uint256 decimals,) = pool.getConfiguration(input.asset).getParamsMemory();

        bytes memory encodedCall = abi.encodeWithSelector(
            IInitializableRToken.initialize.selector,
            pool,
            input.treasury,
            input.asset,
            input.incentivesController,
            decimals,
            input.name,
            input.symbol,
            input.params
        );

        _upgradeTokenImplementation(reserveData.rTokenAddress, input.implementation, encodedCall);

        emit RTokenUpgraded(input.asset, reserveData.rTokenAddress, input.implementation);
    }

    /**
     * @dev Updates the variable debt token implementation for the asset
     *
     */
    function updateVariableDebtToken(UpdateDebtTokenInput calldata input) external {
        onlyProxyAdminOwner();

        DataTypes.ReserveData memory reserveData = pool.getReserveData(input.asset);

        (,,, uint256 decimals,) = pool.getConfiguration(input.asset).getParamsMemory();

        bytes memory encodedCall = abi.encodeWithSelector(
            IInitializableDebtToken.initialize.selector,
            pool,
            input.asset,
            input.incentivesController,
            decimals,
            input.name,
            input.symbol,
            input.params
        );

        _upgradeTokenImplementation(reserveData.variableDebtTokenAddress, input.implementation, encodedCall);

        emit VariableDebtTokenUpgraded(input.asset, reserveData.variableDebtTokenAddress, input.implementation);
    }

    /**
     * @dev Enables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     *
     */
    function enableBorrowingOnReserve(address asset) external {
        onlyPoolAdmin();
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setBorrowingEnabled(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit BorrowingEnabledOnReserve(asset);
    }

    /**
     * @dev Disables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     *
     */
    function disableBorrowingOnReserve(address asset) external {
        onlyPoolAdmin();
        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setBorrowingEnabled(false);

        pool.setConfiguration(asset, currentConfig.data);
        emit BorrowingDisabledOnReserve(asset);
    }

    /**
     * @dev Configures the reserve collateralization parameters
     * all the values are expressed in percentages with two decimals of precision. A valid value is 10000, which means 100.00%
     * @param asset The address of the underlying asset of the reserve
     * @param ltv The loan to value of the asset when used as collateral
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param liquidationBonus The bonus liquidators receive to liquidate this asset. The values is always above 100%. A value of 105%
     * means the liquidator will receive a 5% bonus
     *
     */
    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external {
        onlyPoolAdmin();

        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        //validation of the parameters: the LTV can
        //only be lower or equal than the liquidation threshold
        //(otherwise a loan against the asset would cause instantaneous liquidation)
        if (ltv > liquidationThreshold) revert LPC_INVALID_CONFIGURATION();

        if (liquidationThreshold != 0) {
            //liquidation bonus must be bigger than 100.00%, otherwise the liquidator would receive less
            //collateral than needed to cover the debt
            if (liquidationBonus <= PercentageMath.PERCENTAGE_FACTOR) revert LPC_INVALID_CONFIGURATION();

            //if threshold * bonus is less than PERCENTAGE_FACTOR, it's guaranteed that at the moment
            //a loan is taken there is enough collateral available to cover the liquidation bonus
            if (liquidationThreshold.percentMul(liquidationBonus) > PercentageMath.PERCENTAGE_FACTOR) {
                revert LPC_INVALID_CONFIGURATION();
            }
        } else {
            if (liquidationBonus != 0) revert LPC_INVALID_CONFIGURATION();
            //if the liquidation threshold is being set to 0,
            // the reserve is being disabled as collateral. To do so,
            //we need to ensure no liquidity is deposited
            _checkNoLiquidity(asset);
        }

        currentConfig.setLtv(ltv);
        currentConfig.setLiquidationThreshold(liquidationThreshold);
        currentConfig.setLiquidationBonus(liquidationBonus);

        pool.setConfiguration(asset, currentConfig.data);

        emit CollateralConfigurationChanged(asset, ltv, liquidationThreshold, liquidationBonus);
    }

    /**
     * @dev Activates a reserve
     * @param asset The address of the underlying asset of the reserve
     *
     */
    function activateReserve(address asset) external {
        onlyPoolAdmin();

        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setActive(true);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveActivated(asset);
    }

    /**
     * @dev Deactivates a reserve
     * @param asset The address of the underlying asset of the reserve
     *
     */
    function deactivateReserve(address asset) external {
        onlyPoolAdmin();

        _checkNoLiquidity(asset);

        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setActive(false);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveDeactivated(asset);
    }

    /**
     * @dev Freezes or unfreeze a reserve. A frozen reserve doesn't allow any new deposit, borrow or rate swap
     *  but allows repayments, liquidations, rate rebalances and withdrawals
     * @param asset The address of the underlying asset of the reserve
     *
     */
    function toggleReserveFreeze(address asset, bool shouldFreeze) external {
        onlyPoolAdmin();

        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setFrozen(shouldFreeze);

        pool.setConfiguration(asset, currentConfig.data);
        if (shouldFreeze) {
            emit ReserveFrozen(asset);
        } else {
            emit ReserveUnfrozen(asset);
        }
    }

    /**
     * @dev Updates the reserve factor of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveFactor The new reserve factor of the reserve
     *
     */
    function setReserveFactor(address asset, uint256 reserveFactor) external {
        onlyPoolAdmin();

        DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);

        currentConfig.setReserveFactor(reserveFactor);

        pool.setConfiguration(asset, currentConfig.data);

        emit ReserveFactorChanged(asset, reserveFactor);
    }

    /**
     * @dev Sets the interest rate strategy of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param rateStrategyAddress The new address of the interest strategy contract
     *
     */
    function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress) external {
        onlyPoolAdmin();
        pool.setReserveInterestRateStrategyAddress(asset, rateStrategyAddress);
        emit ReserveInterestRateStrategyChanged(asset, rateStrategyAddress);
    }

    function setRvaultAssetForUnderlying(address asset, address rVaultAsset) external {
        onlyPoolAdmin();

        pool.setRvaultAssetForUnderlying(asset, rVaultAsset);
        emit RvaultAssetForUnderlyingChanged(address(pool), asset, rVaultAsset);
    }

    function _initTokenWithProxy(address implementation, bytes memory initParams, bytes32 _salt)
        internal
        returns (address)
    {
        // Generate salt based on implementation and init params
        bytes32 salt = keccak256(abi.encodePacked(implementation, _salt));

        // Create the proxy initialization code
        bytes memory proxyInitCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode, abi.encode(implementation, proxyAdmin, initParams)
        );

        // Deploy using Create2
        address proxyAddress;
        assembly {
            proxyAddress := create2(0, add(proxyInitCode, 0x20), mload(proxyInitCode), salt)
            if iszero(extcodesize(proxyAddress)) { revert(0, 0) }
        }

        return proxyAddress;
    }

    function _upgradeTokenImplementation(address proxyAddress, address implementation, bytes memory initParams)
        internal
    {
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxyAddress), implementation, initParams);
    }

    function _checkNoLiquidity(address asset) internal view {
        DataTypes.ReserveData memory reserveData = pool.getReserveData(asset);

        uint256 availableLiquidity = IERC20(asset).balanceOf(reserveData.rTokenAddress);

        if (!(availableLiquidity == 0 && reserveData.currentLiquidityRate == 0)) revert LPC_RESERVE_LIQUIDITY_NOT_0();
    }
}
