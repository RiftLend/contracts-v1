import os

files = [
    "packages/contracts/src/interfaces/ILendingPool.sol",
    "packages/contracts/src/interfaces/ILendingPoolAddressesProvider.sol",
    "packages/contracts/src/interfaces/ILendingPoolAddressesProviderRegistry.sol",
    "packages/contracts/src/interfaces/ILendingPoolCollateralManager.sol",
    "packages/contracts/src/interfaces/ILendingPoolConfigurator.sol",
    "packages/contracts/src/interfaces/IRToken.sol",
    "packages/contracts/src/interfaces/IRVaultAsset.sol",
    "packages/contracts/src/interfaces/ISuperAsset.sol",
    "packages/contracts/src/interfaces/ISuperchainAsset.sol",
    "packages/contracts/src/interfaces/ISuperchainTokenBridge.sol",
    "packages/contracts/src/interfaces/IVariableDebtToken.sol",
    "packages/contracts/src/interfaces/ILendingRateOracle.sol",
    "packages/contracts/src/interfaces/IInitializableRToken.sol",
    "packages/contracts/src/interfaces/ICrossL2Prover.sol",
    "packages/contracts/src/interfaces/ICrossL2Inbox.sol",
    "packages/contracts/src/libraries/configuration/ReserveConfiguration.sol",
    "packages/contracts/src/libraries/configuration/UserConfiguration.sol",
    "packages/contracts/src/libraries/logic/GenericLogic.sol",
    "packages/contracts/src/libraries/logic/ReserveLogic.sol",
    "packages/contracts/src/libraries/logic/ValidationLogic.sol",
    "packages/contracts/src/libraries/types/DataTypes.sol",
    "packages/contracts/src/tokenization/RToken.sol",
    "packages/contracts/src/tokenization/VariableDebtToken.sol",
    "packages/contracts/src/L2NativeSuperchainERC20.sol",
    "packages/contracts/src/LendingPool.sol",
    "packages/contracts/src/LendingPoolCollateralManager.sol",
    "packages/contracts/src/LendingPoolConfigurator.sol",
    "packages/contracts/src/LendingPoolStorage.sol",
    "packages/contracts/src/LendingRateOracle.sol",
    "packages/contracts/src/Router.sol",
    "packages/contracts/src/RVaultAsset.sol",
    "packages/contracts/src/SuperAsset.sol",
    "packages/contracts/src/SuperchainERC20.sol"
]

def count_lines_of_code(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()
        return len(lines)

total_lines = 0
table_data = []

for file in files:
    lines = count_lines_of_code(file)
    table_data.append((file, lines))
    total_lines += lines

# Print the table
print(f"{'File':<70} {'Lines of Code':<15}")
print("="*85)
for file, lines in table_data:
    print(f"{file:<70} {lines:<15}")
print("="*85)
print(f"{'Total lines of code':<70} {total_lines:<15}")