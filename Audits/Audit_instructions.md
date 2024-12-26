# RiftLend Audit 1 Scope:

## Contracts in Scope
```
packages
└── contracts
    └── src
        ├── interfaces
        │   ├── ICrossL2Inbox.sol
        │   ├── ICrossL2Prover.sol
        │   ├── IInitializableRToken.sol
        │   ├── ILendingPool.sol
        │   ├── ILendingPoolAddressesProvider.sol
        │   ├── ILendingPoolAddressesProviderRegistry.sol
        │   ├── ILendingPoolCollateralManager.sol
        │   ├── ILendingPoolConfigurator.sol
        │   ├── ILendingRateOracle.sol
        │   ├── IRToken.sol
        │   ├── IRVaultAsset.sol
        │   ├── ISuperAsset.sol
        │   ├── ISuperchainAsset.sol
        │   ├── ISuperchainTokenBridge.sol
        │   └── IVariableDebtToken.sol
        ├── libraries
        │   ├── configuration
        │   │   ├── ReserveConfiguration.sol
        │   │   └── UserConfiguration.sol
        │   ├── logic
        │   │   ├── GenericLogic.sol
        │   │   ├── ReserveLogic.sol
        │   │   └── ValidationLogic.sol
        │   └── types
        │       └── DataTypes.sol
        ├── tokenization
        │   ├── RToken.sol
        │   └── VariableDebtToken.sol
        ├── L2NativeSuperchainERC20.sol
        ├── LendingPool.sol
        ├── LendingPoolCollateralManager.sol
        ├── LendingPoolConfigurator.sol
        ├── LendingPoolStorage.sol
        ├── LendingRateOracle.sol
        ├── Router.sol
        ├── RVaultAsset.sol
        ├── SuperAsset.sol
        └── SuperchainERC20.sol
```

1. Total sLoC in these contracts:
    - 

2. Library dependencies:
    1. [OpenZeppelin v5 contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - (Math Utils, ERC20 tokens, SafeTransfers)
    2. [LayerZero Labs OFT](https://github.com/LayerZero-Labs/oft-evm) - (OFT)
    3. [Aave WadRayMath](https://github.com/aave/protocol-v2/blob/master/contracts/protocol/libraries/math/WadRayMath.sol) - (WadRayMath)

3. External calls:
    1. The contracts will interact with various external protocols and contracts, including but not limited to:
        - Lending protocols
        - Token bridges
        - Oracle services

4. Tokens used:
    1. Assets deposited in the vault will be standard ERC20 tokens, including but not limited to:
        - WETH
        - ETH
        - USDC
        - Other ERC20 tokens

5. Deployments:
    1. The contracts will be deployed on multiple EVM and non-EVM chains, including but not limited to:
        - Ethereum
        - OP Superchains
        - Arbitrum
        - Polygon

6. Audit Documentation:
    1. [LendingPool README](https://github.com/your-repo/lending-pool/README.md)
    2. [SuperAsset Documentation](https://github.com/your-repo/super-asset/README.md)

This template outlines the scope of the audit for the RiftLend project, detailing the contracts to be audited, their dependencies, external interactions, tokens used, deployment targets, and relevant documentation.