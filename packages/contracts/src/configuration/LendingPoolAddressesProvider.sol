// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {SuperOwnable} from "../interop-std/src/auth/SuperOwnable.sol";

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../interfaces/ILendingPoolAddressesProvider.sol";

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Aave Governance
 * @author Aave
 *
 */
contract LendingPoolAddressesProvider is SuperOwnable {
    string private _marketId;
    mapping(bytes32 => address) private _addresses;
    address private _proxyAdmin;
    bytes32 immutable LENDING_POOL; // naming will be like `"OpSuperchain_LENDING_POOL"` or `"EthArb_LENDING_POOL"`
    bytes32 private constant RVAULT_ASSET = "RVAULT_ASSET";
    bytes32 private constant UNDERLYING = "UNDERLYING";
    bytes32 private constant SUPER_ASSET = "SUPER_ASSET";
    bytes32 private constant SUPER_ASSET_ADAPTER = "SUPER_ASSET_ADAPTER";

    bytes32 private constant LENDING_POOL_CONFIGURATOR = "LENDING_POOL_CONFIGURATOR";
    bytes32 private constant POOL_ADMIN = "POOL_ADMIN";
    bytes32 private constant EMERGENCY_ADMIN = "EMERGENCY_ADMIN";
    bytes32 private constant LENDING_POOL_COLLATERAL_MANAGER = "COLLATERAL_MANAGER";
    bytes32 private constant PRICE_ORACLE = "PRICE_ORACLE";
    bytes32 private constant LENDING_RATE_ORACLE = "LENDING_RATE_ORACLE";
    bytes32 private constant RELAYER = "RELAYER";
    bytes32 private constant ROUTER = "ROUTER";

    event SuperAssetUpdated(address indexed superchainAsset);
    event SuperAssetAdapterUpdated(address indexed superchainAssetAdapter);

    event RelayerUpdated(address indexed relayer);
    event RouterUpdated(address indexed router);
    event RVaultAssetUpdated(address indexed RVaultAsset);
    event UnderlyingUpdated(address indexed RVaultAsset);

    constructor(string memory marketId, address initialOwner, address proxyAdmin, bytes32 _lendingPool) {
        _initializeSuperOwner(uint64(block.chainid), initialOwner);
        _setMarketId(marketId);
        _proxyAdmin = proxyAdmin;
        LENDING_POOL = _lendingPool;
    }

    /**
     * @dev Returns the id of the Aave market to which this contracts points to
     * @return The market id
     *
     */
    function getMarketId() external view returns (string memory) {
        return _marketId;
    }

    function getProxyAdmin() external view returns (address) {
        return _proxyAdmin;
    }

    /**
     * @dev Allows to set the market which this LendingPoolAddressesProvider represents
     * @param marketId The market id
     */
    function setMarketId(string memory marketId) external onlyOwner {
        _setMarketId(marketId);
    }

    /**
     * @dev General function to update the implementation of a proxy registered with
     * certain `id`. If there is no proxy registered, it will instantiate one and
     * set as implementation the `implementationAddress`
     * IMPORTANT Use this function carefully, only for ids that don't have an explicit
     * setter function, in order to avoid unexpected consequences
     * @param id The id
     * @param implementationAddress The address of the new implementation
     */
    function setAddressAsProxy(bytes32 id, address implementationAddress, bytes memory params) external onlyOwner {
        _updateImpl(id, implementationAddress, params);
        emit AddressSet(id, implementationAddress, true);
    }

    /**
     * @dev Sets an address for an id replacing the address saved in the addresses map
     * IMPORTANT Use this function carefully, as it will do a hard replacement
     * @param id The id
     * @param newAddress The address to set
     */
    function setAddress(bytes32 id, address newAddress) external onlyOwner {
        _addresses[id] = newAddress;
        emit AddressSet(id, newAddress, false);
    }

    /**
     * @dev Returns an address by id
     * @return The address
     */
    function getAddress(bytes32 id) public view returns (address) {
        return _addresses[id];
    }

    /**
     * @dev Returns the address of the LendingPool proxy
     * @return The LendingPool proxy address
     *
     */
    function getLendingPool() external view returns (address) {
        return getAddress(LENDING_POOL);
    }

    // Set RVaultAsset addresses
    function setRVaultAsset(address rVaultAsset) external onlyOwner {
        _addresses[RVAULT_ASSET] = rVaultAsset;
        emit RVaultAssetUpdated(rVaultAsset);
    }

    function setUnderlying(address underlying) external onlyOwner {
        _addresses[UNDERLYING] = underlying;
        emit UnderlyingUpdated(underlying);
    }

    function getUnderlying() external view returns (address) {
        return getAddress(UNDERLYING);
    }

    function setSuperAsset(address superAsset) external onlyOwner {
        if (LENDING_POOL != keccak256("OpSuperchain_LENDING_POOL")) revert("!allowed");
        _addresses[SUPER_ASSET] = superAsset;
        emit SuperAssetUpdated(superAsset);
    }

    function getSuperAsset() external view returns (address) {
        return getAddress(SUPER_ASSET);
    }

    function setSuperAssetAdapter(address _superAssetAdapter) external onlyOwner {
        _addresses[SUPER_ASSET_ADAPTER] = _superAssetAdapter;
        emit SuperAssetAdapterUpdated(_superAssetAdapter);
    }

    function getSuperAssetAdapter() external view returns (address) {
        return getAddress(SUPER_ASSET_ADAPTER);
    }

    /**
     * @dev Updates the implementation of the LendingPool, or creates the proxy
     * setting the new `pool` implementation on the first time calling it
     * @param pool The new LendingPool implementation
     *
     */
    function setLendingPoolImpl(address pool) external onlyOwner {
        bytes memory params = abi.encodeWithSignature("initialize(address)", address(this));
        _updateImpl(LENDING_POOL, pool, params);
        emit LendingPoolUpdated(pool);
    }

    /**
     * @dev Returns the address of the LendingPoolConfigurator proxy
     * @return The LendingPoolConfigurator proxy address
     *
     */
    function getLendingPoolConfigurator() external view returns (address) {
        return getAddress(LENDING_POOL_CONFIGURATOR);
    }

    /**
     * @dev Updates the implementation of the LendingPoolConfigurator, or creates the proxy
     * setting the new `configurator` implementation on the first time calling it
     * @param configurator The new LendingPoolConfigurator implementation
     *
     */
    function setLendingPoolConfiguratorImpl(address configurator) external onlyOwner {
        bytes memory params = abi.encodeWithSignature("initialize(address,address)", address(this), _proxyAdmin);
        _updateImpl(LENDING_POOL_CONFIGURATOR, configurator, params);
        emit LendingPoolConfiguratorUpdated(configurator);
    }

    /**
     * @dev Returns the address of the LendingPoolCollateralManager. Since the manager is used
     * through delegateCall within the LendingPool contract, the proxy contract pattern does not work properly hence
     * the addresses are changed directly
     * @return The address of the LendingPoolCollateralManager
     *
     */
    function getLendingPoolCollateralManager() external view returns (address) {
        return getAddress(LENDING_POOL_COLLATERAL_MANAGER);
    }

    /**
     * @dev Updates the address of the LendingPoolCollateralManager
     * @param manager The new LendingPoolCollateralManager address
     *
     */
    function setLendingPoolCollateralManager(address manager) external onlyOwner {
        _addresses[LENDING_POOL_COLLATERAL_MANAGER] = manager;
        emit LendingPoolCollateralManagerUpdated(manager);
    }

    /**
     * @dev The functions below are getters/setters of addresses that are outside the context
     * of the protocol hence the upgradable proxy pattern is not used
     *
     */
    function getPoolAdmin() external view returns (address) {
        return getAddress(POOL_ADMIN);
    }

    function setPoolAdmin(address admin) external onlyOwner {
        _addresses[POOL_ADMIN] = admin;
        emit ConfigurationAdminUpdated(admin);
    }

    function getEmergencyAdmin() external view returns (address) {
        return getAddress(EMERGENCY_ADMIN);
    }

    function setEmergencyAdmin(address emergencyAdmin) external onlyOwner {
        _addresses[EMERGENCY_ADMIN] = emergencyAdmin;
        emit EmergencyAdminUpdated(emergencyAdmin);
    }

    function getPriceOracle() external view returns (address) {
        return getAddress(PRICE_ORACLE);
    }

    function setPriceOracle(address priceOracle) external onlyOwner {
        _addresses[PRICE_ORACLE] = priceOracle;
        emit PriceOracleUpdated(priceOracle);
    }

    function getLendingRateOracle() external view returns (address) {
        return getAddress(LENDING_RATE_ORACLE);
    }

    function setLendingRateOracle(address lendingRateOracle) external onlyOwner {
        _addresses[LENDING_RATE_ORACLE] = lendingRateOracle;
        emit LendingRateOracleUpdated(lendingRateOracle);
    }

    function getRelayer() external view returns (address) {
        return getAddress(RELAYER);
    }

    function setRelayer(address relayer) external onlyOwner {
        _addresses[RELAYER] = relayer;
        emit RelayerUpdated(relayer);
    }

    function getPoolType() external view returns (uint8) {
        return LENDING_POOL == keccak256("OpSuperchain_LENDING_POOL") ? 1 : 2;
    }

    /**
     * @dev Internal function to update the implementation of a specific proxied component of the protocol
     * - If there is no proxy registered in the given `id`, it creates the proxy setting `newAdress`
     *   as implementation and calls the initialize() function on the proxy
     * - If there is already a proxy registered, it just updates the implementation to `newAddress` and
     *   calls the initialize() function via upgradeToAndCall() in the proxy
     * @param id The id of the proxy to be updated
     * @param newAddress The address of the new implementation
     *
     */
    function _updateImpl(bytes32 id, address newAddress, bytes memory params) internal {
        address payable proxyAddress = payable(_addresses[id]);

        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(proxyAddress);
        if (proxyAddress == address(0)) {
            proxy = new TransparentUpgradeableProxy(newAddress, _proxyAdmin, params);
            _addresses[id] = address(proxy);
            emit ProxyCreated(id, address(proxy));
        } else {
            ProxyAdmin proxyAdmin = ProxyAdmin(_proxyAdmin);
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), newAddress, params);

            // proxy.upgradeToAndCall(newAddress, params);
        }
    }

    function _setMarketId(string memory marketId) internal {
        _marketId = marketId;
        emit MarketIdSet(marketId);
    }

    function getRouter() external view returns (address) {
        return getAddress(ROUTER);
    }

    function setRouter(address router) external onlyOwner {
        _addresses[ROUTER] = router;
        emit RouterUpdated(router);
    }
}
