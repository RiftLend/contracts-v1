#!/bin/bash

echo "Starting deployments across multiple chains..."

echo "Deploying to Optimism Sepolia..."
forge script scripts/batchDeploymentScript/batchDeploy.s.sol --rpc-url https://opt-sepolia.g.alchemy.com/v2/muWMumYKuC6W7Oa572HjryTPZMMLbPK3  --sender 0x5377679614bc0BB997d82D11D79A87e3c5695848 

echo "Deploying to Arbitrum Sepolia..."
forge script scripts/batchDeploymentScript/batchDeploy.s.sol --rpc-url https://arb-sepolia.g.alchemy.com/v2/muWMumYKuC6W7Oa572HjryTPZMMLbPK3  --sender 0x5377679614bc0BB997d82D11D79A87e3c5695848 

echo "Deploying to Base Sepolia..."
forge script scripts/batchDeploymentScript/batchDeploy.s.sol --rpc-url https://base-sepolia.g.alchemy.com/v2/muWMumYKuC6W7Oa572HjryTPZMMLbPK3  --sender 0x5377679614bc0BB997d82D11D79A87e3c5695848 

echo "Deploying to Unichain Sepolia..."
forge script scripts/batchDeploymentScript/batchDeploy.s.sol --rpc-url https://unichain-sepolia.g.alchemy.com/v2/muWMumYKuC6W7Oa572HjryTPZMMLbPK3  --sender 0x5377679614bc0BB997d82D11D79A87e3c5695848 

echo "All deployments completed!"