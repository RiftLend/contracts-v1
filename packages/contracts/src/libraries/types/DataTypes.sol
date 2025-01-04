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
        uint8 pool_type;
        address superAsset;
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

    enum Chain_Cluster_Types {
        NONE,
        CROSS,
        INTRA
    }

    enum INTRA_CLUSTER_SERVICE_CHOICE {
        SUPERCHAIN,
        OFT
    }

    struct BungeeBridgeOrder {
        bytes32 id;
        // 0 for INIT - initiated
        // 1 for PENDING - sent order from source chain
        // 2 for EXECUTED received at destination chain and funds transferred
        uint8 status;
        address user;
        address receiver;
        uint256 srcChainId;
        uint256 destChainId;
        uint256 timestamp;
        uint256 amount;
    }
}
