// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

// Import all contracts from your project
import {TestERC20} from "test/utils/TestERC20.sol";
import {EventValidator} from "src/libraries/EventValidator.sol";
import {SuperAsset} from "src/SuperAsset.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {DefaultReserveInterestRateStrategy} from "src/DefaultReserveInterestRateStrategy.sol";
import {MockPriceOracle} from "test/utils/MockPriceOracle.sol";
import {LendingPool} from "src/LendingPool.sol";
import {LendingPoolConfigurator} from "src/LendingPoolConfigurator.sol";
import {RVaultAsset} from "src/RVaultAsset.sol";
import {RToken} from "src/tokenization/RToken.sol";
import {VariableDebtToken} from "src/tokenization/VariableDebtToken.sol";
import {LendingPoolCollateralManager} from "src/LendingPoolCollateralManager.sol";
import {Router} from "src/Router.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {BatchDataTypes} from "./BatchDataTypes.sol";

/// @notice Batch Deployer 1 deploys contracts needed for underlying assets and pricing:
///         TestERC20, EventValidator, SuperAsset, ProxyAdmin, LendingPoolAddressesProvider,
///         DefaultReserveInterestRateStrategy, and MockPriceOracle.

library Create2Helper {
    function _implSalt(string memory salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(salt));
    }

    function deployContractWithArgs(
        string memory contractName,
        string memory salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal returns (address) {
        return _deployWithCreate2(contractName, salt, creationCode, constructorArgs);
    }

    function _deployWithCreate2(
        string memory, /*contractName*/
        string memory salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal returns (address) {
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 saltBytes = _implSalt(salt);

        address preComputedAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), saltBytes, keccak256(initCode)))))
        );

        if (preComputedAddress.code.length > 0) {
            return preComputedAddress;
        }

        address addr;
        assembly {
            addr := create2(0, add(initCode, 0x20), mload(initCode), saltBytes)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }

        return addr;
    }
}

contract BatchDeployer1 {
    address public underlying;
    address public eventValidator;
    address public superAsset;
    address public proxyAdmin;
    address public lendingPoolAddressesProvider;
    address public defaultReserveInterestRateStrategy;
    address public mockPriceOracle;
    // Group all deployed addresses in a struct for easier access.

    struct Addresses {
        address underlying;
        address eventValidator;
        address superAsset;
        address proxyAdmin;
        address lendingPoolAddressesProvider;
        address defaultReserveInterestRateStrategy;
        address mockPriceOracle;
    }

    constructor(BatchDataTypes.Batch1Params memory params) {
        underlying = Create2Helper.deployContractWithArgs(
            "TestERC20", params.underlyingSalt, type(TestERC20).creationCode, abi.encode(params.ownerAddress)
        );

        proxyAdmin = Create2Helper.deployContractWithArgs(
            "ProxyAdmin", params.proxyAdminSalt, type(ProxyAdmin).creationCode, abi.encode(params.ownerAddress)
        );
        lendingPoolAddressesProvider = Create2Helper.deployContractWithArgs(
            "LendingPoolAddressesProvider",
            params.lpAddressProviderSalt,
            type(LendingPoolAddressesProvider).creationCode,
            abi.encode(params.marketId, params.ownerAddress, params.ownerAddress, params.lpType)
        );

        eventValidator = Create2Helper.deployContractWithArgs(
            "EventValidator",
            params.eventValidatorSalt,
            type(EventValidator).creationCode,
            abi.encode(params.ownerAddress)
        );

        superAsset = Create2Helper.deployContractWithArgs(
            "SuperAsset", params.superAssetSalt, type(SuperAsset).creationCode, abi.encode(params.ownerAddress)
        );

        defaultReserveInterestRateStrategy = Create2Helper.deployContractWithArgs(
            "DefaultReserveInterestRateStrategy",
            params.strategySalt,
            type(DefaultReserveInterestRateStrategy).creationCode,
            abi.encode(params.ownerAddress)
        );

        mockPriceOracle = Create2Helper.deployContractWithArgs(
            "MockPriceOracle", params.oracleSalt, type(MockPriceOracle).creationCode, abi.encode(params.ownerAddress)
        );
    }

    // Return all deployed addresses as one struct.
    function getDeployedAddresses() external view returns (Addresses memory) {
        return Addresses({
            underlying: underlying,
            eventValidator: eventValidator,
            superAsset: superAsset,
            proxyAdmin: proxyAdmin,
            lendingPoolAddressesProvider: lendingPoolAddressesProvider,
            defaultReserveInterestRateStrategy: defaultReserveInterestRateStrategy,
            mockPriceOracle: mockPriceOracle
        });
    }
}

/// @notice Batch Deployer 2 deploys the core lending pool implementation and its configurator.

contract BatchDeployer2 {
    address public lendingPoolImpl;
    address public lendingPoolConfigurator;

    constructor(string memory lpSalt, string memory lpConfiguratorSalt) {
        lendingPoolImpl =
            Create2Helper.deployContractWithArgs("LendingPool", lpSalt, type(LendingPool).creationCode, "");

        lendingPoolConfigurator = Create2Helper.deployContractWithArgs(
            "LendingPoolConfigurator", lpConfiguratorSalt, type(LendingPoolConfigurator).creationCode, ""
        );
    }

    struct Addresses {
        address lendingPoolImpl;
        address lendingPoolConfigurator;
    }

    function getDeployedAddresses() external view returns (Addresses memory) {
        return Addresses({lendingPoolImpl: lendingPoolImpl, lendingPoolConfigurator: lendingPoolConfigurator});
    }
}
/// @notice Batch Deployer 3 deploys the tokenization contracts: RVaultAsset, RToken, and VariableDebtToken.

contract BatchDeployer3 {
    address public rVaultAsset;
    address public rToken;
    address public variableDebtToken;

    constructor(
        string memory rVaultAssetSalt,
        string memory rTokenSalt,
        string memory variableDebtTokenSalt,
        address ownerAddress
    ) {
        rVaultAsset = Create2Helper.deployContractWithArgs(
            "RVaultAsset", rVaultAssetSalt, type(RVaultAsset).creationCode, abi.encode(ownerAddress)
        );
        rToken = Create2Helper.deployContractWithArgs("RToken", rTokenSalt, type(RToken).creationCode, "");
        variableDebtToken = Create2Helper.deployContractWithArgs(
            "VariableDebtToken", variableDebtTokenSalt, type(VariableDebtToken).creationCode, ""
        );
    }

    struct Addresses {
        address rVaultAsset;
        address rToken;
        address variableDebtToken;
    }

    function getDeployedAddresses() external view returns (Addresses memory) {
        return Addresses({rVaultAsset: rVaultAsset, rToken: rToken, variableDebtToken: variableDebtToken});
    }
}

/// @notice Batch Deployer 4 deploys the collateral manager and the Router (with proxy).
///         The Router’s proxy initialization requires addresses deployed in other batches.
///         Pass in lendingPool, lendingPoolAddressesProvider, eventValidator, and proxyAdmin.
contract BatchDeployer4 {
    address public lendingPoolCollateralManager;
    address public router;

    constructor(string memory routerSalt, string memory lpCollateralManagerSalt) {
        lendingPoolCollateralManager = Create2Helper.deployContractWithArgs(
            "LendingPoolCollateralManager", lpCollateralManagerSalt, type(LendingPoolCollateralManager).creationCode, ""
        );

        router = Create2Helper.deployContractWithArgs("Router", routerSalt, type(Router).creationCode, "");
    }

    struct Addresses {
        address lendingPoolCollateralManager;
        address router;
    }

    function getDeployedAddresses() external view returns (Addresses memory) {
        return Addresses({lendingPoolCollateralManager: lendingPoolCollateralManager, router: router});
    }
}
