# RiftLend Audit Guidelines

## About

RiftLend is a multichain lending platform. Leveraging Aave V2's battle-tested architecture, RiftLend revolutionizes cross-chain DeFi operations by offering a unified, chain-agnostic lending experience with seamless cross-chain functionality.

This audit will be focused on core contracts of Riftlend being developed.

The current branch for the latest changes is [tabish/nits](https://github.com/RiftLend/contracts-v1/tree/tabish/nits).

## Scope

```fs
packages
└── contracts
    └── src
        ├── interfaces
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
        ├── LendingPool.sol
        ├── LendingPoolCollateralManager.sol
        ├── LendingPoolConfigurator.sol
        ├── LendingPoolStorage.sol
        ├── LendingRateOracle.sol
        ├── Router.sol
        ├── RVaultAsset.sol
        └── SuperAsset.sol
```

## nSLOC

```fs

File                                                                        Lines of Code  
===================================================================================== 
File                                                                   Lines of Code  
=====================================================================================
packages/contracts/src/interfaces/ILendingPool.sol                     174
packages/contracts/src/interfaces/ILendingPoolAddressesProvider.sol    42
packages/contracts/src/interfaces/ILendingPoolAddressesProviderRegistry.sol 9
packages/contracts/src/interfaces/ILendingPoolCollateralManager.sol    26
packages/contracts/src/interfaces/ILendingPoolConfigurator.sol         64
packages/contracts/src/interfaces/IRToken.sol                          22
packages/contracts/src/interfaces/IRVaultAsset.sol                     18
packages/contracts/src/interfaces/ISuperAsset.sol                      14
packages/contracts/src/interfaces/ISuperchainAsset.sol                 16
packages/contracts/src/interfaces/IVariableDebtToken.sol               15
packages/contracts/src/interfaces/ILendingRateOracle.sol               5
packages/contracts/src/interfaces/IInitializableRToken.sol             28
packages/contracts/src/libraries/configuration/ReserveConfiguration.sol 139
packages/contracts/src/libraries/configuration/UserConfiguration.sol   49
packages/contracts/src/libraries/logic/GenericLogic.sol                154
packages/contracts/src/libraries/logic/ReserveLogic.sol                200
packages/contracts/src/libraries/logic/ValidationLogic.sol             235
packages/contracts/src/libraries/types/DataTypes.sol                   27
packages/contracts/src/tokenization/RToken.sol                         330
packages/contracts/src/tokenization/VariableDebtToken.sol              126
packages/contracts/src/LendingPool.sol                                 572
packages/contracts/src/LendingPoolCollateralManager.sol                189
packages/contracts/src/LendingPoolConfigurator.sol                     284
packages/contracts/src/LendingPoolStorage.sol                          14
packages/contracts/src/LendingRateOracle.sol                           22
packages/contracts/src/Router.sol                                      298
packages/contracts/src/RVaultAsset.sol                                 167
packages/contracts/src/SuperAsset.sol                                  36
=====================================================================================
Total lines of code                                                    3275
```

## Library dependencies:

1. [OpenZeppelin v5 contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - (Math Utils, ERC20 tokens, SafeTransfers)
2. [LayerZero Labs OFT](https://github.com/LayerZero-Labs/oft-evm) - (OFT)
3. [Polymer Prover](https://docs.polymerlabs.org/docs/build/prove-api/prover-contract)
4. [Socket Bridge API](https://docs.bungee.exchange/socket-api/guides/bungee-smart-contract-integration)
5. [Aave V2 WadRayMath](https://github.com/aave/protocol-v2/blob/master/contracts/protocol/libraries/math/WadRayMath.sol)

## External calls:

The contracts will interact with various external protocols and contracts, including but not limited to:

    - DeFi protocols
    - Token bridges
    - Oracle services

## Tokens used:

Assets deposited in the vault will be standard ERC20 tokens, including but not limited to: - WETH - ETH - USDC - Other ERC20 tokens

## Deployments:

The contracts will be deployed on multiple EVM and non-EVM chains, including but not limited to: - OP Superchains - Ethereum - Arbitrum

more will be added later

1. Audit Documentation:
   1. [Stale Documentation](https://github.com/RiftLend/contracts-v1/tree/tabish/nits?tab=readme-ov-file#riftlend)
   2. [Official Docs (beta)](https://docs.riftlend.com/)