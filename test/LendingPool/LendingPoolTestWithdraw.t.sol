// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {IRVaultAsset, RVaultAssetInitializeParams} from "src/interfaces/IRVaultAsset.sol";
import {IOFT} from "src/libraries/helpers/layerzero/IOFT.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPoolConfigurator} from "src/interfaces/ILendingPoolConfigurator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "src/interfaces/ILendingPool.sol";
import {IAaveIncentivesController} from "src/interfaces/IAaveIncentivesController.sol";

import {DataTypes} from "src/libraries/types/DataTypes.sol";
import {UserConfiguration} from "src/libraries/configuration/UserConfiguration.sol";
import {Identifier, EventValidator, ValidationMode} from "src/libraries/EventValidator.sol";
import {
    Origin, MessagingReceipt, ILayerZeroEndpointV2
} from "src/libraries/helpers/layerzero/ILayerZeroEndpointV2.sol";
import {LendingPoolTestBase} from "./LendingPoolTestBase.t.sol";
import {RVaultAsset} from "src/RVaultAsset.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPool} from "src/LendingPool.sol";
import {Router} from "src/Router.sol";
import {LendingPoolConfigurator} from "src/LendingPoolConfigurator.sol";
import {RToken} from "src/tokenization/RToken.sol";
import {VariableDebtToken} from "src/tokenization/VariableDebtToken.sol";
import {DefaultReserveInterestRateStrategy} from "src/DefaultReserveInterestRateStrategy.sol";
import "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {EventUtils} from "../utils/libraries/EventUtils.sol";

interface IOAppSetPeer {
    function setPeer(uint32 _eid, bytes32 _peer) external;
    function endpoint() external view returns (ILayerZeroEndpointV2 iEndpoint);
}

/**
 * @title LendingPoolTestWithdraw
 * @notice Test contract for cross-chain withdrawal functionality in the lending pool system
 * @dev Tests the complete flow of deposits and withdrawals across different chains using LayerZero
 */
contract LendingPoolTestWithdraw is LendingPoolTestBase {
    // ======== Cross-Chain Vault Assets ========
    RVaultAsset aRVaultAsset; // Vault asset for chain A
    RVaultAsset bRVaultAsset; // Vault asset for chain B

    // ======== Chain Identifiers ========
    uint32 private aEid = 1; // Endpoint ID for chain A
    uint32 private bEid = 2; // Endpoint ID for chain B

    // ======== LendingPool Components ========
    LendingPool proxyLp1; // LendigPool Proxy contract for chain A
    LendingPool proxyLp2; // LendigPool Proxy contract for chain B

    // ======== Cross-Chain Routing ========
    Router router1; // Router for chain A
    Router router2; // Router for chain B

    // ======== Pool Configuration ========
    LendingPoolConfigurator proxyConfigurator1; // Configurator for chain A
    LendingPoolConfigurator proxyConfigurator2; // Configurator for chain B
    LendingPoolConfigurator lpConfigurator1;
    LendingPoolConfigurator lpConfigurator2;
    RToken rTokenImpl1;
    RToken rTokenImpl2;
    VariableDebtToken variableDebtTokenImpl1;
    VariableDebtToken variableDebtTokenImpl2;
    DataTypes.ReserveData reserveData;
    DataTypes.ReserveData reserveData2;
    address rToken1;
    address rToken2;
    DataTypes.WithdrawEventParams withdrawEventParams;
    DataTypes.CrosschainWithdrawData crossChainWithdrawData;
    DataTypes.DepositEventParams depositEventParams;
    address onBehalfOf;
    uint16 referralCode;
    bytes eventData;
    bytes32 _selector;

    /**
     * @notice Sets up the complete test environment
     * @dev Initializes all necessary contracts and configurations for cross-chain testing
     */
    function setUp() public virtual override {
        // Initialize base test setup
        super.setUp();

        // ======== Initial User Setup ========
        // Provide test users with initial ETH balances
        vm.deal(bootStrapper, 100000 ether); //100k eth
        console.log(address(bootStrapper).balance);

        vm.prank(bootStrapper);
        {
            bool success;
            (success,) = user1.call{value: INITIAL_BALANCE}("");
            require(success, "Failed to send ETH to user1");
            vm.prank(bootStrapper);
            (success,) = user2.call{value: INITIAL_BALANCE}("");
            require(success, "Failed to send ETH to user2");
        }

        // Initialize LayerZero endpoints using UltraLightNode
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // ======== Deploy Address Providers ========
        // Deploy address providers for both chains
        lpAddressProvider1 =
            new LendingPoolAddressesProvider("TUSDC1", owner, proxyAdmin, keccak256("OpSuperchain_LENDING_POOL"));
        lpAddressProvider2 =
            new LendingPoolAddressesProvider("TUSDC2", owner, proxyAdmin, keccak256("OpSuperchain_LENDING_POOL"));

        // ======== Deploy & Initialize LendingPools ========
        vm.startPrank(owner);
        // Deploy implementations
        implementationLp1 = new LendingPool();
        implementationLp2 = new LendingPool();

        // Label contracts for better trace outputs
        vm.label(address(implementationLp1), "implementationLp1");
        vm.label(address(implementationLp2), "implementationLp2");

        vm.stopPrank();

        // ======== Configure LendingPool Proxies ========
        vm.startPrank(owner);

        // Set implementations in providers
        lpAddressProvider1.setLendingPoolImpl(address(implementationLp1));
        lpAddressProvider2.setLendingPoolImpl(address(implementationLp2));

        // Get proxy references
        proxyLp1 = LendingPool(lpAddressProvider1.getLendingPool());
        proxyLp2 = LendingPool(lpAddressProvider2.getLendingPool());

        // Label proxies for better trace outputs
        vm.label(address(proxyLp1), "proxyLp1");
        vm.label(address(proxyLp2), "proxyLp2");

        vm.stopPrank();

        // ======== Deploy & Configure Pool Configurators ========
        vm.startPrank(owner);

        // Deploy configurator implementations
        lpConfigurator1 = new LendingPoolConfigurator();
        lpConfigurator2 = new LendingPoolConfigurator();

        // Initialize configurators
        lpConfigurator1.initialize(ILendingPoolAddressesProvider(address(lpAddressProvider1)), proxyAdmin);
        lpConfigurator2.initialize(ILendingPoolAddressesProvider(address(lpAddressProvider2)), proxyAdmin);

        // Set configurator implementations in providers
        lpAddressProvider1.setLendingPoolConfiguratorImpl(address(lpConfigurator1));
        lpAddressProvider2.setLendingPoolConfiguratorImpl(address(lpConfigurator2));

        // Get configurator proxy references
        proxyConfigurator1 = LendingPoolConfigurator(lpAddressProvider1.getLendingPoolConfigurator());
        proxyConfigurator2 = LendingPoolConfigurator(lpAddressProvider2.getLendingPoolConfigurator());

        vm.stopPrank();

        // ======== Deploy & Initialize Routers ========
        vm.startPrank(owner);

        // Deploy routers with unique salts
        router1 = new Router{salt: "router1"}();
        router2 = new Router{salt: "router2"}();

        // Initialize routers with respective components
        router1.initialize(address(proxyLp1), address(lpAddressProvider1), address(eventValidator));
        router2.initialize(address(proxyLp2), address(lpAddressProvider2), address(eventValidator));

        vm.stopPrank();

        // ======== Configure Address Providers ========
        vm.startPrank(owner);

        // Configure chain A provider
        lpAddressProvider1.setPoolAdmin(poolAdmin1);
        lpAddressProvider1.setRelayerStatus(relayer, true);
        lpAddressProvider1.setRouter(address(router1));

        // Configure chain B provider
        lpAddressProvider2.setPoolAdmin(poolAdmin1);
        lpAddressProvider2.setRelayerStatus(relayer, true);
        lpAddressProvider2.setRouter(address(router2));

        vm.stopPrank();

        // ======== Deploy RVaultAssets ========
        uint32[] memory lzEids;
        uint256[] memory lzEidChains;

        vm.startPrank(owner);

        // Deploy and initialize vault asset for chain A
        aRVaultAsset = RVaultAsset(payable(_deployOApp(type(RVaultAsset).creationCode, abi.encode(owner))));
        aRVaultAsset.initialize(
            RVaultAssetInitializeParams(
                address(superAsset),
                ILendingPoolAddressesProvider(address(lpAddressProvider1)),
                address(endpoints[aEid]),
                _delegate,
                rVaultAssetTokenName1,
                rVaultAssetTokenSymbol1,
                underlyingAssetDecimals,
                1 days,
                1000 ether,
                200000,
                500000,
                owner,
                lzEidChains,
                lzEids
            )
        );

        // Deploy and initialize vault asset for chain B
        bRVaultAsset = RVaultAsset(payable(_deployOApp(type(RVaultAsset).creationCode, abi.encode(owner))));
        bRVaultAsset.initialize(
            RVaultAssetInitializeParams(
                address(superAsset),
                ILendingPoolAddressesProvider(address(lpAddressProvider2)),
                address(endpoints[bEid]),
                _delegate,
                rVaultAssetTokenName2,
                rVaultAssetTokenSymbol2,
                underlyingAssetDecimals,
                1 days,
                1000 ether,
                200000,
                500000,
                owner,
                lzEidChains,
                lzEids
            )
        );

        vm.stopPrank();

        // Bootstraping initial ETH to vault assets for lzCalls
        {
            bool success;
            vm.prank(bootStrapper);
            (success,) = payable(aRVaultAsset).call{value: 10 ether}("");
            require(success, "Failed to send ETH to aRVaultAsset");

            vm.prank(bootStrapper);
            (success,) = payable(bRVaultAsset).call{value: 10 ether}("");
            require(success, "Failed to send ETH to bRVaultAsset");
        }
        // ======== Configure Cross-Chain Communication ========
        // Setup peer connections between vault assets
        address[] memory ofts = new address[](2);
        ofts[0] = address(aRVaultAsset);
        ofts[1] = address(bRVaultAsset);
        for (uint256 i = 0; i < ofts.length; i++) {
            IOAppSetPeer localOApp = IOAppSetPeer(ofts[i]);
            for (uint256 j = 0; j < ofts.length; j++) {
                if (i == j) continue;
                IOAppSetPeer remoteOApp = IOAppSetPeer(ofts[j]);
                uint32 remoteEid = (remoteOApp.endpoint()).eid();
                vm.prank(owner);
                localOApp.setPeer(remoteEid, addressToBytes32(address(remoteOApp)));
            }
        }

        // ======== Deploy Token Components ========
        vm.startPrank(owner);

        // Deploy and initialize RTokens
        console.log("deploying rTokenImpl1");
        rTokenImpl1 = new RToken{salt: "rToken1"}();
        console.log("deploying rTokenImpl2");
        rTokenImpl2 = new RToken{salt: "rToken2"}();

        // Deploy and initialize Variable Debt Tokens
        variableDebtTokenImpl1 = new VariableDebtToken{salt: "variableDebtTokenImpl1"}();
        variableDebtTokenImpl2 = new VariableDebtToken{salt: "variableDebtTokenImpl2"}();
        vm.stopPrank();

        // ======== Deploy Interest Rate Strategy ========
        // Deploy strategy with initial parameters
        vm.prank(owner);
        strategy = address(new DefaultReserveInterestRateStrategy(owner));
        vm.prank(owner);
        DefaultReserveInterestRateStrategy(strategy).initialize(
            ILendingPoolAddressesProvider(address(lpAddressProvider1)),
            0.8 * 1e27, // optimalUtilizationRate
            0.02 * 1e27, // baseVariableBorrowRate
            0.04 * 1e27, // variableRateSlope1
            0.75 * 1e27 // variableRateSlope2
        );
        vm.label(strategy, "DefaultReserveInterestRateStrategy");

        // ======== Initialize Reserves ========
        // Prepare initialization input for chain A
        ILendingPoolConfigurator.InitReserveInput[] memory pool1_input =
            new ILendingPoolConfigurator.InitReserveInput[](1);
        pool1_input[0] = ILendingPoolConfigurator.InitReserveInput({
            rTokenName: rTokenName1,
            rTokenSymbol: rTokenSymbol1,
            variableDebtTokenImpl: address(variableDebtTokenImpl1),
            variableDebtTokenName: variableDebtTokenName,
            variableDebtTokenSymbol: variableDebtTokenSymbol,
            interestRateStrategyAddress: strategy,
            treasury: treasury,
            incentivesController: incentivesController,
            superAsset: address(superAsset),
            underlyingAsset: address(aRVaultAsset),
            underlyingAssetDecimals: underlyingAssetDecimals,
            underlyingAssetName: underlyingAssetName,
            params: "v",
            salt: "salt",
            rTokenImpl: address(rTokenImpl1),
            eventValidator: address(eventValidator)
        });
        // ======== Initialize and Activate Reserves ========
        vm.prank(poolAdmin1);
        proxyConfigurator1.batchInitReserve(pool1_input);

        // Prepare initialization input for chain B
        pool1_input[0] = ILendingPoolConfigurator.InitReserveInput({
            rTokenName: rTokenName2,
            rTokenSymbol: rTokenSymbol2,
            variableDebtTokenImpl: address(variableDebtTokenImpl2),
            variableDebtTokenName: variableDebtTokenName,
            variableDebtTokenSymbol: variableDebtTokenSymbol,
            interestRateStrategyAddress: strategy,
            treasury: treasury,
            incentivesController: incentivesController,
            superAsset: address(superAsset),
            underlyingAsset: address(address(bRVaultAsset)),
            underlyingAssetDecimals: underlyingAssetDecimals,
            underlyingAssetName: underlyingAssetName,
            params: "v",
            salt: "salt",
            rTokenImpl: address(rTokenImpl2),
            eventValidator: address(eventValidator)
        });

        // ======== Initialize and Activate Reserves ========
        vm.startPrank(poolAdmin1);
        proxyConfigurator2.batchInitReserve(pool1_input);

        reserveData = proxyLp1.getReserveData(address(aRVaultAsset));
        rToken1 = reserveData.rTokenAddress;
        require(rToken1 != address(0), "RToken not initialized in reserves");

        reserveData2 = proxyLp2.getReserveData(address(bRVaultAsset));
        rToken2 = reserveData2.rTokenAddress;

        // Activate reserves and set RVaultAsset mappings
        proxyConfigurator1.activateReserve(address(aRVaultAsset));
        proxyConfigurator2.activateReserve(address(bRVaultAsset));
        proxyConfigurator1.setRvaultAssetForUnderlying(address(underlyingAsset), address(aRVaultAsset));
        proxyConfigurator2.setRvaultAssetForUnderlying(address(underlyingAsset), address(bRVaultAsset));

        vm.stopPrank();

        // Bootsrapping initial gas funds
        {
            bool success;
            vm.prank(bootStrapper);
            (success,) = address(rToken1).call{value: 100 ether}("");
            require(success, "Failed to send ETH to rToken1");

            vm.prank(bootStrapper);
            (success,) = address(rToken2).call{value: 100 ether}("");
            require(success, "Failed to send ETH to rToken1");
        }

        // ======== Cross-Chain Configuration ========
        // Set chain ID mappings for cross-chain communication
        (aRVaultAsset).setChainToEid(bEid, bEid);
        (bRVaultAsset).setChainToEid(aEid, aEid);

        // ======== Initial Token Distribution ========
        // Setup initial balances for both vault assets
        ofts[0] = address(aRVaultAsset);
        ofts[1] = address(bRVaultAsset);

        // Initialize user balances and approvals for each vault
        for (uint256 i = 0; i < ofts.length; i++) {
            address rVaultAsset = ofts[i];

            // Provide initial underlying token balances
            deal(address(underlyingAsset), user1, INITIAL_BALANCE);
            deal(address(underlyingAsset), user2, INITIAL_BALANCE);
            deal(address(underlyingAsset), liquidityProvider, INITIAL_BALANCE);

            // Setup approvals for user1
            vm.startPrank(user1);
            IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
            IERC20(address(superAsset)).approve(rVaultAsset, type(uint256).max);
            vm.stopPrank();

            // Setup approvals for user2
            vm.startPrank(user2);
            IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
            IERC20(address(superAsset)).approve(rVaultAsset, type(uint256).max);
            vm.stopPrank();

            // Setup approvals for lp
            vm.startPrank(liquidityProvider);
            IERC20(address(underlyingAsset)).approve(address(superAsset), type(uint256).max);
            IERC20(address(superAsset)).approve(rVaultAsset, type(uint256).max);
            vm.stopPrank();

            // Handle superAsset deposits if required
            if (IRVaultAsset(rVaultAsset).pool_type() == 1) {
                vm.prank(user1);
                superAsset.deposit(user1, DEPOSIT_AMOUNT);
                vm.prank(user2);
                superAsset.deposit(user2, DEPOSIT_AMOUNT);
                vm.prank(liquidityProvider);
                superAsset.deposit(liquidityProvider, DEPOSIT_AMOUNT);
            }

            // Initial deposits to RVaultAssets
            vm.prank(user1);
            IRVaultAsset(rVaultAsset).deposit(DEPOSIT_AMOUNT, user1);
            vm.prank(user2);
            IRVaultAsset(rVaultAsset).deposit(DEPOSIT_AMOUNT, user2);
        }
    }

    /**
     * @notice Tests the complete cross-chain withdrawal flow
     * @dev Verifies deposit setup, withdrawal execution, and cross-chain message handling
     */
    DataTypes.CrosschainDepositData crosschainDepositData;

    function test_lpWithdraw() public {
        // ======== Test Configuration ========
        // Setup deposit parameters
        onBehalfOf = user1;
        referralCode = 0;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = aEid;

        // Set test chain context
        vm.chainId(aEid);

        // ======== Initial Deposit Setup ========
        // Approve spending
        vm.prank(user1);
        underlyingAsset.approve(address(proxyLp1), amounts[0]);

        // Record events and execute deposit
        vm.recordLogs();
        vm.prank(user1);
        router1.deposit(address(underlyingAsset), amounts, onBehalfOf, referralCode, chainIds);

        // ======== Process Deposit Via Relayer ========
        Identifier[] memory _identifier = new Identifier[](1);
        bytes[] memory _eventData = new bytes[](1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256[] memory _logindex = new uint256[](1);
        _logindex[0] = 0;

        _identifier[0] =
            Identifier(address(0x4200000000000000000000000000000000000023), block.number, 0, block.timestamp, aEid);

        // Decode deposit event data
        (crosschainDepositData) = abi.decode(entries[0].data, (DataTypes.CrosschainDepositData));

        // Prepare and dispatch event

        _selector = ILendingPool.CrossChainDeposit.selector;
        _eventData[0] = abi.encode(
            _selector,
            crosschainDepositData.fromChainId,
            crosschainDepositData.sender,
            crosschainDepositData.asset,
            crosschainDepositData.amount,
            crosschainDepositData.onBehalfOf,
            crosschainDepositData.referralCode
        );
        // relay the information using relayer calling dispatch function on LendingPool through router
        console.log("deposit dispatch ");
        vm.recordLogs();
        vm.prank(relayer);
        router1.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        entries = vm.getRecordedLogs();
        eventData = EventUtils.findEventsBySelector(entries, ILendingPool.Deposit.selector)[0];

        (depositEventParams) = abi.decode(eventData, (DataTypes.DepositEventParams));

        _eventData[0] = abi.encode(
            ILendingPool.Deposit.selector,
            depositEventParams.user,
            depositEventParams.reserve,
            depositEventParams.amount,
            depositEventParams.onBehalfOf,
            depositEventParams.referral,
            depositEventParams.mintMode,
            depositEventParams.amountScaled
        );
        // sync state of deposit for updating crosschain balances
        console.log("sync state of deposit for updating crosschain balances");
        vm.chainId(bEid);
        vm.prank(relayer);
        router1.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        /// assert cross chain balances of rtoken
        uint256 totalCrosschainUnderlyingAssets = RToken(
            payable(proxyLp1.getReserveData(address(aRVaultAsset)).rTokenAddress)
        ).totalCrosschainUnderlyingAssets();
        // depositParams.amount on source and depositParams.amount on other chain
        // so exptectedCrosschainBalance = 2*depositParams.amount
        uint256 expectedCrosschainBalance = 2 * depositEventParams.amount;

        assert(totalCrosschainUnderlyingAssets == expectedCrosschainBalance);

        // ======== Execute Withdrawal ========
        // Record events and initiate withdrawal
        vm.chainId(aEid);
        vm.recordLogs();
        vm.prank(user1);
        router1.withdraw(address(underlyingAsset), amounts, user2, bEid, chainIds);

        // ======== Process Withdrawal Via Relayer ========
        _identifier = new Identifier[](1);
        _eventData = new bytes[](1);
        entries = vm.getRecordedLogs();
        _logindex = new uint256[](1);
        _logindex[0] = 0;

        _identifier[0] =
            Identifier(address(0x4200000000000000000000000000000000000023), block.number, 0, block.timestamp, aEid);

        // Decode withdrawal event data
        (crossChainWithdrawData) = abi.decode(entries[0].data, (DataTypes.CrosschainWithdrawData));

        _selector = ILendingPool.CrossChainWithdraw.selector;
        _eventData[0] = abi.encode(
            _selector,
            crossChainWithdrawData.fromChainId,
            crossChainWithdrawData.sender,
            crossChainWithdrawData.asset,
            crossChainWithdrawData.amount,
            crossChainWithdrawData.to,
            crossChainWithdrawData.toChainId
        );

        // Record and process withdrawal events
        console.log("withdraw dispatch");
        vm.recordLogs();
        vm.prank(relayer);
        router1.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);
        // ======== Verify Withdrawal Events ========
        entries = vm.getRecordedLogs();
        eventData = EventUtils.findEventsBySelector(entries, ILendingPool.Withdraw.selector)[0];

        (withdrawEventParams) = abi.decode(eventData, (DataTypes.WithdrawEventParams));

        // Verify withdrawal parameters
        assert(withdrawEventParams.user == address(user1));
        assert(withdrawEventParams.to == address(user2));
        assert(withdrawEventParams.amount == amounts[0]);

        _eventData[0] = abi.encode(
            ILendingPool.Withdraw.selector,
            withdrawEventParams.user,
            withdrawEventParams.reserve,
            withdrawEventParams.to,
            withdrawEventParams.amount,
            withdrawEventParams.mode,
            withdrawEventParams.amountScaled
        );
        vm.chainId(bEid);
        vm.prank(relayer);
        router1.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        /// assert cross chain balances of rtoken
        totalCrosschainUnderlyingAssets = RToken(payable(proxyLp1.getReserveData(address(aRVaultAsset)).rTokenAddress))
            .totalCrosschainUnderlyingAssets();
        console.log("totalCrosschainUnderlyingAssets", totalCrosschainUnderlyingAssets);
        assert(totalCrosschainUnderlyingAssets == 0);

        // ======== Verify Cross-Chain Messages ========
        verifyPackets(bEid, addressToBytes32(address(bRVaultAsset)));
    }
}
