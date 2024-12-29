// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

library DataTypes {
    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 currentLiquidityRate;
        uint128 currentVariableBorrowRate;
        uint40 lastUpdateTimestamp;
        address rTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint8 id;
    }

    enum Action_type {
        DEPOSIT,
        WITHDRAW,
        BORROW,
        TRANSFER,
        REPAY,
        LIQUIDATION,
        SET_USER_RESERVE_AS_COLLATERAL
    }

    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct UserConfigurationMap {
        uint256 data;
    }

    enum InterestRateMode {
        NONE,
        VARIABLE
    }

    enum Chain_Cluster_Types{
        NONE,
        INTER,
        INTRA
    }

}
