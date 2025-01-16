# RiftLend Audit Guidelines

## About

RiftLend is a multichain lending platform. Leveraging Aave V2's battle-tested architecture, RiftLend revolutionizes cross-chain DeFi operations by offering a unified, chain-agnostic lending experience with seamless cross-chain functionality.

This audit will be focused on core contracts of Riftlend being developed.

The current branch for the latest changes is [main](https://github.com/RiftLend/contracts-v1/tree/main).

## Scope

```fs
    src
    ├── libraries
    │   ├── configuration
    │   │   ├── ReserveConfiguration.sol
    │   │   └── UserConfiguration.sol
    │   ├── logic
    │   │   ├── GenericLogic.sol
    │   │   ├── OFTLogic.sol
    │   │   ├── ReserveLogic.sol
    │   │   └── ValidationLogic.sol
    │   └── types
    │       └── DataTypes.sol
    ├── tokenization
    │   ├── DelegationAwareAToken.sol
    │   ├── IncentivizedERC20.sol
    │   ├── RToken.sol
    │   └── VariableDebtToken.sol
    ├── configuration
    │   └── LendingPoolAddressesProvider.sol
    ├── EventValidator.sol
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
File                                                             Lines of Code
=============================================================================
src/libraries/configuration/ReserveConfiguration.sol                 121        
src/libraries/configuration/UserConfiguration.sol                    49
src/libraries/logic/GenericLogic.sol                                 168      
src/libraries/logic/ReserveLogic.sol                                 180
src/libraries/logic/ValidationLogic.sol                              214  
src/libraries/types/DataTypes.sol                                    59
src/tokenization/RToken.sol                                          277 
src/tokenization/VariableDebtToken.sol                               128 
src/tokenization/IncentivizedERC20.sol                               122  
src/tokenization/DelegationAwareAToken.sol                           14
src/configuration/LendingPoolAddressesProvider.sol                   137  
src/libraries/logic/GenericLogic.sol                                 168     
src/libraries/logic/OFTLogic.sol                                     20
src/libraries/logic/ReserveLogic.sol                                 180     
src/libraries/logic/ValidationLogic.sol                              214        
src/libraries/EventValidator.sol                                     53
src/LendingPool.sol                                                  486        
src/LendingPoolCollateralManager.sol                                 193        
src/LendingPoolConfigurator.sol                                      239        
src/LendingPoolStorage.sol                                           15
src/LendingRateOracle.sol                                            22
src/Router.sol                                                       234        
src/RVaultAsset.sol                                                  149        
src/SuperAsset.sol                                                   59

========================================================================
Total lines of code                                                3501       

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

## Auditor Notes

### Changes in the libraries
We have used `Layerzero V1 and V2` libraries to implement cross chain interoperability. However , we have changed somethings in their code and put it in `src/libraries/helpers/layerzero` folder . The key changes are made in `layerzero v2` contracts
    - Using `Solady` contracts to remove conflicts with some of our contracts that uses solady's code for gas efficiency
    - We have made OFT contracts upgradable to serve the purpose of child contracts be upgradable .
 
 It is to note that from `Layerzero v1` we had to use it for a one specific instance of `ILayerzeroUtraLightNodeV2.sol` which is used inside `DVN.sol` from lz V2 . Changing DVN would have been hectic to manage all the cascading deps change so we directly installed the v1 too but just for you to understand that the real dependency issues might be in how we use layerzero v2.
