// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestBase.t.sol";
import {EventUtils} from "../utils/libraries/EventUtils.sol";
import {Deposit} from "src/interfaces/ILendingPool.sol";

/*´:°•.°+.•´.:˚.°.˚•´.°:°•.°•.•´.:˚.°.˚•´.°:°•.°+.•´.:*/
/*        Lending Pool Deposit Functions               */
/*´:°•.°+.•´.:˚.°.˚•´.°:°•.°•.•´.:˚.°.˚•´.°:°•.°+.•´.:*/

contract LendingPoolTestDeposit is LendingPoolTestBase {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    function test_lpDeposit() public {
        Identifier[] memory _identifier = new Identifier[](1);
        bytes[] memory _eventData = new bytes[](1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256[] memory _logindex = new uint256[](1);

        super.setUp();
        // ########### Prepare deposit params
        (uint256[] memory amounts, address onBehalfOf, uint16 referralCode, uint256[] memory chainIds) =
            getActionXConfig();

        vm.prank(user1);
        IERC20(underlyingAsset).approve(address(proxyLp), amounts[0]);

        // ########### Deposit through router ###########
        // Start the recorder
        vm.recordLogs();
        // initiate deposit
        vm.prank(user1);
        router.deposit(address(underlyingAsset), amounts, onBehalfOf, referralCode, chainIds);
        entries = vm.getRecordedLogs();

        console.log("preparing relayer deposit dispatch");
        _logindex[0] = 0;
        _identifier[0] = Identifier(
            address(0x4200000000000000000000000000000000000023), block.number, 0, block.timestamp, block.chainid
        );
        console.log("decoding");
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
        // deposit dispatch and perform actual lp.deposit
        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(rVaultAsset1);
        address rToken = reserveData.rTokenAddress;

        assertEq(IERC20(rVaultAsset1).balanceOf(rToken), amounts[0]);

        DataTypes.UserConfigurationMap memory userConfig = proxyLp.getUserConfiguration(onBehalfOf);
        assert(userConfig.isUsingAsCollateralOrBorrowing(reserveData.id) == true);
        // sync deposit states across other chains

        entries = vm.getRecordedLogs();
        bytes memory eventData;
        eventData = EventUtils.findEventsBySelector(entries, Deposit.selector)[0];
        address _user;
        uint16 _referral;
        uint256 _mintMode;
        uint256 _amountScaled;

        (_user, _asset, _amount, _onBehalfOf, _referral, _mintMode, _amountScaled) =
            abi.decode(eventData, (address, address, uint256, address, uint16, uint256, uint256));

        _eventData[0] =
            abi.encode(Deposit.selector, _user, _asset, _amount, _onBehalfOf, _referral, _mintMode, _amountScaled);
        // sync state of deposit for updating crosschain balances
        console.log("sync state of deposit for updating crosschain balances");
        vm.chainId(supportedChains[1].chainId);
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        /// assert cross chain balances of rtoken
        assert(
            RToken(address(proxyLp.getReserveData(address(rVaultAsset1)).rTokenAddress)).totalCrosschainUnderlyingAssets(
            ) == _amount
        );
    }

    function getActionXConfig()
        public
        view
        returns (uint256[] memory amounts, address onBehalfOf, uint16 referralCode, uint256[] memory chainIds)
    {
        amounts = new uint256[](1);
        amounts[0] = DEPOSIT_AMOUNT;
        onBehalfOf = user1;
        referralCode = 0;
        chainIds = new uint256[](1);
        chainIds[0] = supportedChains[0].chainId;
    }
}
