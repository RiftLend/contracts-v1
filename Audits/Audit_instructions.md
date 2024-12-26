# RiftLend Audit 1 Scope:

## About
RiftLend is a next-generation decentralized lending and borrowing protocol built natively for the OP super-chain ecosystem. Leveraging Aave V2's battle-tested architecture, RiftLend revolutionizes cross-chain DeFi operations by offering a unified, chain-agnostic lending experience with seamless cross-chain functionality.

This audit will be focused on core contracts of Riftlend being developed.

The current branch for the latest changes is [tabish/nits](https://github.com/RiftLend/contracts-v1/tree/tabish/nits).

## Scope

```fs
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

## nSLOC

```fs
File                                                                   Lines of Code  
===================================================================================== 
src/interfaces/ILendingPool.sol                          327
src/interfaces/ILendingPoolAddressesProvider.sol         90
src/interfaces/ILendingPoolAddressesProviderRegistry.sol 24
src/interfaces/ILendingPoolCollateralManager.sol         78
src/interfaces/ILendingPoolConfigurator.sol              181
src/interfaces/IRToken.sol                               121
src/interfaces/IRVaultAsset.sol                          20
src/interfaces/ISuperAsset.sol                           54
src/interfaces/ISuperchainAsset.sol                      58
src/interfaces/ISuperchainTokenBridge.sol                27
src/interfaces/IVariableDebtToken.sol                    78
src/interfaces/ILendingRateOracle.sol                    21
src/interfaces/IInitializableRToken.sol                  63
src/interfaces/ICrossL2Prover.sol                        16
src/interfaces/ICrossL2Inbox.sol                         76
src/libraries/configuration/ReserveConfiguration.sol      311
src/libraries/configuration/UserConfiguration.sol        111
src/libraries/logic/GenericLogic.sol                     239
src/libraries/logic/ReserveLogic.sol                     339
src/libraries/logic/ValidationLogic.sol                  387
src/libraries/types/DataTypes.sol                        32
src/tokenization/RToken.sol                              548
src/tokenization/VariableDebtToken.sol                   267
src/L2NativeSuperchainERC20.sol                          72
src/LendingPool.sol                                      1117
src/LendingPoolCollateralManager.sol                     282
src/LendingPoolConfigurator.sol                          490
src/LendingPoolStorage.sol                               64
src/LendingRateOracle.sol                                30
src/Router.sol                                           564
src/RVaultAsset.sol                                      239
src/SuperAsset.sol                                       51
src/SuperchainERC20.sol                                  51
=====================================================================================
Total lines of code                                                         6428

```


## Library dependencies:
1. [OpenZeppelin v5 contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - (Math Utils, ERC20 tokens, SafeTransfers)
2. [LayerZero Labs OFT](https://github.com/LayerZero-Labs/oft-evm) - (OFT)
3. [Aave V2 WadRayMath](https://github.com/aave/protocol-v2/blob/master/contracts/protocol/libraries/math/WadRayMath.sol) - (WadRayMath)

## External calls:
The contracts will interact with various external protocols and contracts, including but not limited to:

    - Lending protocols
    - Token bridges
    - Oracle services

## Tokens used:
Assets deposited in the vault will be standard ERC20 tokens, including but not limited to:
    - WETH
    - ETH
    - USDC
    - Other ERC20 tokens

## Deployments:
The contracts will be deployed on multiple EVM and non-EVM chains, including but not limited to:
    - OP Superchains
    - Ethereum
    - Arbitrum

more will be added later

1. Audit Documentation:
    1. [Draft Documentation](https://github.com/RiftLend/contracts-v1/blob/main/README.md)
    2. [Official Docs (beta)](https://docs.riftlend.com/)
