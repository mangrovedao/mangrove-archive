# Assumes the ETHEREUM_NODE_URL environment variable points to an archive node for Ethereum mainnet
# and that a local node that has forked mainnet is running:
#
#   export ETHEREUM_NODE_URL=https://eth-mainnet.alchemyapi.io/v2/<key>
#   npx hardhat node --fork $ETHEREUM_NODE_URL
#
npx hardhat --network localhost test test/ethereum/test-mainnet.js
