#!/bin/bash

echo "Starting deployments across multiple chains..."

echo "Deploying to Optimism Sepolia..."
forge script scripts/batchDeploymentScript/batchDeploy.s.sol --rpc-url https://opt-sepolia.g.alchemy.com/v2/muWMumYKuC6W7Oa572HjryTPZMMLbPK3  --sender 0xcbc771976e3623ad236A4D8556897C47925B2Aaa 

echo "Deploying to Arbitrum Sepolia..."
forge script scripts/batchDeploymentScript/batchDeploy.s.sol --rpc-url https://arb-sepolia.g.alchemy.com/v2/muWMumYKuC6W7Oa572HjryTPZMMLbPK3  --sender 0xcbc771976e3623ad236A4D8556897C47925B2Aaa 

echo "Deploying to Base Sepolia..."
forge script scripts/batchDeploymentScript/batchDeploy.s.sol --rpc-url https://base-sepolia.g.alchemy.com/v2/muWMumYKuC6W7Oa572HjryTPZMMLbPK3  --sender 0xcbc771976e3623ad236A4D8556897C47925B2Aaa 

echo "Deploying to Unichain Sepolia..."
forge script scripts/batchDeploymentScript/batchDeploy.s.sol --rpc-url https://unichain-sepolia.g.alchemy.com/v2/muWMumYKuC6W7Oa572HjryTPZMMLbPK3  --sender 0xcbc771976e3623ad236A4D8556897C47925B2Aaa 

echo "All deployments completed!"