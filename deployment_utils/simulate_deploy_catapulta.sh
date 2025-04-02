#!/bin/bash

echo "Starting deployments across multiple chains..."

echo "Deploying to Optimism Sepolia..."
catapulta script scripts/batchDeploymentScript/batchDeploy.s.sol --network optimismSepolia  --simulate

echo "Deploying to Arbitrum Sepolia..."
catapulta script scripts/batchDeploymentScript/batchDeploy.s.sol --network arbitrumSepolia  --simulate

echo "Deploying to Base Sepolia..."
catapulta script scripts/batchDeploymentScript/batchDeploy.s.sol --network baseSepolia --simulate

echo "Deploying to Unichain Sepolia..."
catapulta script scripts/batchDeploymentScript/batchDeploy.s.sol --network unichainTestnet  --simulate

echo "All deployments completed!"
