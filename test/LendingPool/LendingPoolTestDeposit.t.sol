// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "./LendingPoolTestBase.t.sol";
import {EventUtils} from "../utils/libraries/EventUtils.sol";
import {ILendingPool} from "src/interfaces/ILendingPool.sol";

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
        uint256[] memory amounts;
        uint256[] memory chainIds;
        address onBehalfOf;
        uint16 referralCode;
        address rToken;

        super.setUp();

        // ########### Prepare deposit params
        (amounts, onBehalfOf, referralCode, chainIds) = getActionXConfig();

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

        (DataTypes.CrosschainDepositData memory params) = abi.decode(entries[0].data, (DataTypes.CrosschainDepositData));
        bytes32 _selector = ILendingPool.CrossChainDeposit.selector;

        _eventData[0] = abi.encode(
            _selector,
            params.fromChainId,
            params.sender,
            params.asset,
            params.amount,
            params.onBehalfOf,
            params.referralCode
        );
        // deposit dispatch and perform actual lp.deposit
        vm.recordLogs();
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        DataTypes.ReserveData memory reserveData = proxyLp.getReserveData(rVaultAsset1);
        rToken = reserveData.rTokenAddress;

        assertEq(IERC20(rVaultAsset1).balanceOf(rToken), amounts[0]);

        DataTypes.UserConfigurationMap memory userConfig = proxyLp.getUserConfiguration(params.onBehalfOf);
        assert(userConfig.isUsingAsCollateralOrBorrowing(reserveData.id) == true);
        // sync deposit states across other chains

        entries = vm.getRecordedLogs();
        bytes memory eventData;
        eventData = EventUtils.findEventsBySelector(entries, ILendingPool.Deposit.selector)[0];

        (DataTypes.DepositEventParams memory depositParams) = abi.decode(eventData, (DataTypes.DepositEventParams));

        _eventData[0] = abi.encode(
            ILendingPool.Deposit.selector,
            depositParams.user,
            depositParams.asset,
            depositParams.amount,
            depositParams.onBehalfOf,
            depositParams.referral,
            depositParams.mintMode,
            depositParams.amountScaled
        );
        // sync state of deposit for updating crosschain balances
        console.log("sync state of deposit for updating crosschain balances");
        vm.chainId(supportedChains[1].chainId);
        vm.prank(relayer);
        router.dispatch(ValidationMode.CUSTOM, _identifier, _eventData, bytes(""), _logindex);

        /// assert cross chain balances of rtoken
        assert(
            RToken(address(proxyLp.getReserveData(address(rVaultAsset1)).rTokenAddress)).totalCrosschainUnderlyingAssets(
            ) == depositParams.amount
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
