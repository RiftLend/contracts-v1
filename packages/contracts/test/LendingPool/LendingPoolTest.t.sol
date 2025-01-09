// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "../Base.t.sol";
import {DataTypes} from "../../src/libraries/types/DataTypes.sol";
import {UserConfiguration} from "../../src/libraries/configuration/UserConfiguration.sol";
import {Identifier} from "../../src/libraries/EventValidator.sol";
import "forge-std/Vm.sol";

import {CrossChainDeposit, CrossChainWithdraw} from "../../src/interfaces/ILendingPool.sol";
import {ValidationMode} from "../../src/libraries/EventValidator.sol";

contract LendingPoolTest is Base {
    using UserConfiguration for DataTypes.UserConfigurationMap;
    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant DEPOSIT_AMOUNT = 100 ether;


    /// @dev tests that the user can deposit underlying asset to the pool
    /// @dev tests that the user config is updated correctly
    /// @dev tests that the rToken has the correct balance

    function setUp() public override {
        super.setUp();
        deal(address(underlyingAsset), user1, INITIAL_BALANCE);
        deal(address(underlyingAsset), user2, INITIAL_BALANCE);

    }
    function test_lpDeposit() public {
        // ########### Prepare deposit params
        (uint256[] memory amounts, address onBehalfOf, uint16 referralCode, uint256[] memory chainIds) =
            getActionXConfig();

        address rVaultAsset = proxyLp.getRVaultAssetOrRevert(address(underlyingAsset));

        vm.prank(user1);
        IERC20(underlyingAsset).approve(address(proxyLp), amounts[0]);
        //   router.deposit()
        // ########### Deposit through router ###########
        // Start the recorder
        vm.recordLogs();
        // initiate deposit
        vm.prank(user1);
        router.deposit(address(underlyingAsset), amounts, onBehalfOf, referralCode, chainIds);
        Identifier[] memory _identifier = new Identifier[](1);
        bytes[] memory _eventData = new bytes[](1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256[] memory _logindex = new uint256[](1);
        _logindex[0] = 0;

        _identifier[0] = Identifier(
            address(0x4200000000000000000000000000000000000023), block.number, 0, block.timestamp, block.chainid
        );

        (
            uint256 _fromChainId,
            address _sender,
            address _asset,
            uint256 _amount,
            address _onBehalfOf,
            uint16 _referralCode
        ) = abi.decode(entries[0].data, (uint256, address, address, uint256, address, uint16));
        bytes32 _selector = CrossChainDeposit.selector;

        _eventData[0] =
            abi.encode(_selector, _fromChainId, bytes32(0), _sender, _asset, _amount, _onBehalfOf, _referralCode);

        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(rVaultAsset1);
        address rToken = reserveData.rTokenAddress;

        assertEq(IERC20(rVaultAsset1).balanceOf(rToken), amounts[0]);

        // TODO:test is the userconfig for the rVaultAsset correct?
        DataTypes.UserConfigurationMap memory userConfig = proxyLp.getUserConfiguration(onBehalfOf);
        assert(userConfig.isUsingAsCollateralOrBorrowing(reserveData.id) == true);
    }

    function test_lpWithdraw() public {
        test_lpDeposit();
        (uint256[] memory amounts, address onBehalfOf,, uint256[] memory chainIds) = getActionXConfig();

        // ########### Withdraw through router ###########
        // Start the recorder
        vm.recordLogs();
        // initiate deposit
        vm.prank(user1);
        router.withdraw(address(underlyingAsset), amounts, onBehalfOf, block.chainid, chainIds);

        Identifier[] memory _identifier = new Identifier[](1);
        bytes[] memory _eventData = new bytes[](1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256[] memory _logindex = new uint256[](1);
        _logindex[0] = 0;

        _identifier[0] = Identifier(
            address(0x4200000000000000000000000000000000000023), block.number, 0, block.timestamp, block.chainid
        );
        // event CrossChainWithdraw( uint256 fromChainId, address sender, address asset, uint256 amount, address to, uint256 toChainId);
        (uint256 _fromChainId, address _sender, address _asset, uint256 _amount, address _to, uint256 _toChainId) =
            abi.decode(entries[0].data, (uint256, address, address, uint256, address, uint256));
        bytes32 _selector = CrossChainWithdraw.selector;

        _eventData[0] = abi.encode(_selector, _fromChainId, bytes32(0), _sender, _asset, _amount, _to, _toChainId);

        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(rVaultAsset1);
        address rToken = reserveData.rTokenAddress;

        assertEq(IERC20(rVaultAsset1).balanceOf(rToken), amounts[0]);
    }

    /// @dev tests that the rVaultAsset has the correct underlying
    /// @dev for rVaultAsset1 the underlying is superasset
    /// @dev for rVaultAsset1 the underlying is superasset
    function test_lpRVaultUnderlyingIsCorrect() public {
        // for rVaultAsset1 the underlying is superasset
        assertEq(IRVaultAsset(rVaultAsset1).asset(), address(superAsset));
        // for rVaultAsset1 the underlying is superasset
        assertEq(IRVaultAsset(rVaultAsset2).asset(), address(underlyingAsset));
    }

    // TODO:test does the rVaultAsset correctly mint and burn ... with the token type like superasset / underlying?
    /// @dev tests that the rVaultAsset correctly mint and burn ... with the token type like superasset / underlying?
    /// @dev for rVaultAsset1 the underlying is superasset
    /// @dev for rVaultAsset2 the underlying is superasset
    function test_lpRVaultMintBurnCorrectly() public {
        // for rVaultAsset1 the underlying is superasset
        vm.prank(user1);
        IERC20(address(underlyingAsset)).approve(address(superAsset), 10 ether);
        vm.prank(user1);
        superAsset.deposit(user1, 10 ether);

        uint256 user1SuperAssetBalanceBefore = IERC20(address(superAsset)).balanceOf(user1);

        vm.prank(user1);
        IERC20(address(superAsset)).approve(address(rVaultAsset1), 10 ether);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset1).mint(10 ether, user1);

        uint256 user1SuperAssetBalanceAfter = IERC20(address(superAsset)).balanceOf(user1);

        assert(IERC20(rVaultAsset1).balanceOf(user1) == 10 ether);
        assert(user1SuperAssetBalanceAfter == user1SuperAssetBalanceBefore - 10 ether);

        // for rVaultAsset2 the underlying is superasset

        uint256 user1UnderlyingBalanceBefore = IERC20(underlyingAsset).balanceOf(user1);
        vm.prank(user1);
        IERC20(underlyingAsset).approve(address(rVaultAsset2), 10 ether);
        vm.prank(user1);
        IRVaultAsset(rVaultAsset2).mint(10 ether, user1);

        uint256 user1UnderlyingBalanceAfter = IERC20(address(underlyingAsset)).balanceOf(user1);

        assert(IERC20(rVaultAsset2).balanceOf(user1) == 10 ether);
        assert(user1UnderlyingBalanceAfter == user1UnderlyingBalanceBefore - 10 ether);
    }

    function getActionXConfig()
        internal
        view
        returns (uint256[] memory amounts, address onBehalfOf, uint16 referralCode, uint256[] memory chainIds)
    {
        amounts = new uint256[](1);
        amounts[0] = 10 ether;
        onBehalfOf = user1;
        referralCode = 0;
        chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
    }
}
