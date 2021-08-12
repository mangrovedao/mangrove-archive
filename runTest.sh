# Assumes the ETHEREUM_NODE_URL environment variable points to an archive node for Ethereum mainnet, e.g. by
#
#   export ETHEREUM_NODE_URL=https://eth-mainnet.alchemyapi.io/v2/<key>
#
npx hardhat test test/ethereum/test-mainnet.js
