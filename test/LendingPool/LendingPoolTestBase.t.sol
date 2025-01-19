// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import "../Base.t.sol";
import {DataTypes} from "../../src/libraries/types/DataTypes.sol";
import {UserConfiguration} from "../../src/libraries/configuration/UserConfiguration.sol";
import {Identifier} from "../../src/libraries/EventValidator.sol";
import "forge-std/Vm.sol";

import {CrossChainDeposit, CrossChainWithdraw} from "../../src/interfaces/ILendingPool.sol";
import {ValidationMode} from "../../src/libraries/EventValidator.sol";

contract LendingPoolTestBase is Base {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    /// @dev tests that the user can deposit underlying asset to the pool
    /// @dev tests that the user config is updated correctly
    /// @dev tests that the rToken has the correct balance

    function setUp() public virtual override {
        super.setUp();
        deal(address(underlyingAsset), user1, INITIAL_BALANCE);
        deal(address(underlyingAsset), user2, INITIAL_BALANCE);
        deal(address(underlyingAsset), liquidator, INITIAL_BALANCE);
        deal(address(underlyingAsset), liquidityProvider, INITIAL_BALANCE);
    }
}
