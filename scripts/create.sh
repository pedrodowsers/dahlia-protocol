#!/bin/sh
set -x

# https://github.com/foundry-rs/foundry/issues/9439
forge create src/core/contracts/Dahlia.sol:Dahlia \
  --broadcast  \
  --private-key ${DEPLOYER_PRIVATE_KEY} \
  --rpc-url https://bartio.rpc.berachain.com \
  --verify \
  --verifier custom \
  --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80084/etherscan' \
  --verifier-api-key "verifyContract" \
  --chain 80084 \
  --constructor-args "0x56929D12646A2045de60e16AA28b8b4c9Dfb0441" "0x7C12A2c6fb7a4a5Fa6c482CA403D7701289471f2"
