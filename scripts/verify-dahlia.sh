#!/bin/sh
set -x

# MarketMath
#forge verify-contract \
#  0x4eB1349a08F1148945D6344d0a7e99B2BFe1B0f3 \
#  ./src/core/helpers/MarketMath.sol:MarketMath \
#  --verifier-url "https://api.routescan.io/v2/network/testnet/evm/80000/etherscan" \
#  --etherscan-api-key "verifyContract" \
#  --watch \
#  --num-of-optimizations 200 \
#  --compiler-version "v0.8.27"

# WrappedVault
#forge verify-contract \
#  0xdf1f36377f2cc51993879713f405bd34e3abd35f \
#  ./src/royco/contracts/WrappedVault.sol:WrappedVault \
#  --verifier-url "https://api.routescan.io/v2/network/testnet/evm/80000/etherscan" \
#  --etherscan-api-key "verifyContract" \
#  --num-of-optimizations 200 \
#  --compiler-version "v0.8.27+commit.40a35a09"

## DahliaRegistry
#ENCODED_ARGS=$(cast abi-encode \
#  "constructor(address)" \
#  0x56929D12646A2045de60e16AA28b8b4c9Dfb0441)
#
#forge verify-contract \
#  0x88dd1ae59f48199920b49bb9a1ce7db9226fe8fc \
#  ./src/core/contracts/DahliaRegistry.sol:DahliaRegistry \
#  --verifier-url "https://api.routescan.io/v2/network/testnet/evm/80000/etherscan" \
#  --etherscan-api-key "verifyContract" \
#  --num-of-optimizations 200 \
#  --compiler-version "v0.8.27+commit.5d80cfab" \
#  --constructor-args $ENCODED_ARGS
#
# Dahlia
ENCODED_ARGS=$(cast abi-encode \
  "constructor(address, address)" \
  0x56929D12646A2045de60e16AA28b8b4c9Dfb0441 \
  0x7C12A2c6fb7a4a5Fa6c482CA403D7701289471f2)

forge verify-contract \
  0x0a7e67a977cf9ab1de3781ec58625010050e446e \
  ./src/core/contracts/Dahlia.sol:Dahlia \
  --verifier-url "https://api.routescan.io/v2/network/testnet/evm/80000/etherscan" \
  --num-of-optimizations 200 \
  --via-ir \
  --watch \
  --compiler-version "v0.8.27" \
  --libraries "src/core/helpers/MarketMath.sol:MarketMath:0x4eB1349a08F1148945D6344d0a7e99B2BFe1B0f3" \
  --constructor-args "$ENCODED_ARGS"\
  --chain 80000

#  --constructor-args "$ENCODED_ARGS"

# WrappedVaultFactory
#ENCODED_ARGS=$(cast abi-encode \
#  "constructor(address, address, uint256, uint256, address, address, address)" \
#  0x2D8E6f1A1840233507Cbf57Bc30529DAb37461Db \
#  0x56929D12646A2045de60e16AA28b8b4c9Dfb0441 \
#  10000000000000000 \
#  20000000000000000 \
#  0x56929D12646A2045de60e16AA28b8b4c9Dfb0441 \
#  0x19112AdBDAfB465ddF0b57eCC07E68110Ad09c50 \
#  0x2D9FE428c7d0Eeb3B5f265b101Fc119e06D0d9f9 \
#  )
#
#forge verify-contract \
#  0x8164c2FF405E15e8d9f000562D1bCF2f6345183c \
#  ./src/royco/contracts/WrappedVaultFactory.sol:WrappedVaultFactory \
#  --verifier-url "https://api.routescan.io/v2/network/testnet/evm/80084/etherscan" \
#  --etherscan-api-key "verifyContract" \
#  --num-of-optimizations 200 \
#  --skip-is-verified-check \
#  --watch \
#  --delay 10 \
#  --compiler-version "v0.8.28" \
#  --constructor-args $ENCODED_ARGS

## IRMFactory
#forge verify-contract \
#  0xeda157aaa70e211bda032f4d3fbba047ac540ddc \
#  ./src/irm/contracts/IrmFactory.sol:IrmFactory \
#  --verifier-url "https://api.routescan.io/v2/network/testnet/evm/80000/etherscan" \
#  --etherscan-api-key "verifyContract" \
#  --num-of-optimizations 200 \
#  --compiler-version "v0.8.27+commit.5d80cfab"

# VariableIrm
#ENCODED_ARGS=$(cast abi-encode \
#  "constructor((uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256))" \
#  "(88000, 92000, 90000, 604800, 15824704600, 158247046000, 31649410, 200000000000000000)")
#
#forge verify-contract \
#  0xaca13f8896b69e47816a7e3db9be89ce876982ce \
#  ./src/irm/contracts/VariableIrm.sol:VariableIrm \
#  --verifier-url "https://api.routescan.io/v2/network/testnet/evm/80000/etherscan" \
#  --etherscan-api-key "verifyContract" \
#  --num-of-optimizations 200 \
#  --compiler-version "v0.8.27+commit.5d80cfab" \
#  --constructor-args $ENCODED_ARGS
