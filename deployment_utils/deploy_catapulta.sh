#!/bin/bash

echo "Starting deployments across multiple chains..."

echo "Deploying to Optimism Sepolia..."
catapulta script scripts/batchDeploymentScript/batchDeploy.s.sol --network optimismSepolia  

echo "Deploying to Arbitrum Sepolia..."
catapulta script scripts/batchDeploymentScript/batchDeploy.s.sol --network arbitrumSepolia  

echo "Deploying to Base Sepolia..."
catapulta script scripts/batchDeploymentScript/batchDeploy.s.sol --network baseSepolia 

echo "Deploying to Unichain Sepolia..."
catapulta script scripts/batchDeploymentScript/batchDeploy.s.sol --network unichainTestnet  

echo "All deployments completed!"
