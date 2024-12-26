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
packages/contracts/src/interfaces/ILendingPool.sol                              325
packages/contracts/src/interfaces/ILendingPoolAddressesProvider.sol             90
packages/contracts/src/interfaces/ILendingPoolAddressesProviderRegistry.sol     24
packages/contracts/src/interfaces/ILendingPoolCollateralManager.sol             78
packages/contracts/src/interfaces/ILendingPoolConfigurator.sol                  181
packages/contracts/src/interfaces/IRToken.sol                                   120
packages/contracts/src/interfaces/IRVaultAsset.sol                              20
packages/contracts/src/interfaces/ISuperAsset.sol                               54
packages/contracts/src/interfaces/ISuperchainAsset.sol                          58
packages/contracts/src/interfaces/IVariableDebtToken.sol                        78
packages/contracts/src/interfaces/ILendingRateOracle.sol                        21
packages/contracts/src/interfaces/IInitializableRToken.sol                      63
packages/contracts/src/libraries/configuration/ReserveConfiguration.sol         311
packages/contracts/src/libraries/configuration/UserConfiguration.sol            111
packages/contracts/src/libraries/logic/GenericLogic.sol                         240
packages/contracts/src/libraries/logic/ReserveLogic.sol                         339
packages/contracts/src/libraries/logic/ValidationLogic.sol                      383
packages/contracts/src/libraries/types/DataTypes.sol                            32
packages/contracts/src/tokenization/RToken.sol                                  551
packages/contracts/src/tokenization/VariableDebtToken.sol                       244
packages/contracts/src/LendingPool.sol                                          915
packages/contracts/src/LendingPoolCollateralManager.sol                         282
packages/contracts/src/LendingPoolConfigurator.sol                              490
packages/contracts/src/LendingPoolStorage.sol                                   64
packages/contracts/src/LendingRateOracle.sol                                    30
packages/contracts/src/Router.sol                                               584
packages/contracts/src/RVaultAsset.sol                                          239
packages/contracts/src/SuperAsset.sol                                           51
=====================================================================================
Total lines of code                                                             5978

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