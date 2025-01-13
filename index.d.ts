import { Address } from 'viem'

export const deployment: {
  deployedAddress: Address // address of test token contract (TUSDC)
  ownerAddress: Address // address of owner of deployed test token contract
  rTokenAddress: Address // address of deployed aToken contract implementation
  stableDebtTokenAddress: Address // address of deployed stable debt token contract implementation
  variableDebtTokenAddress: Address // address of deployed variable debt token contract implementation
  lendingPoolAddressesProviderAddress: Address // address of deployed lending pool addresses provider contract
  superchainAssetAddress: Address // address of deployed superchain asset contract
  lendingPoolAddress: Address // address of deployed lending pool contract
  proxyAdminAddress: Address // address of deployed proxy admin contract
  lendingPoolConfiguratorAddress: Address // address of deployed lending pool configurator contract
  defaultReserveInterestRateStrategyAddress: Address // address of deployed default reserve interest rate strategy contract
  lendingRateOracleAddress: Address // address of deployed lending rate oracle contract
  routerAddress: Address // address of deployed router contract
  routerImplAddress: Address // address of deployed router implementation contract
}
