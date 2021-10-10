Hardhat Mangrove is a set of Hardhat-based development tools for Mangrove. They make it easy to build and test Mangrove-based dApps.

# Usage

Install as development dependency:

```
# NPM
npm install --save-dev @giry/hardhat-mangrove

# Yarn
yarn add --dev @giry/hardhat-mangrove
```

## Mocha integration tests

You can write integration tests against Mangrove on a local in-process Hardhat network by using the provided [Mocha](https://mochajs.org/) Root Hooks. Just `require` the root hooks when you run Mocha, e.g.:

```
mocha --require "@giry/hardhat-mangrove/mocha/hooks/integration-test-hooks" <your Mocha args here>
```

# Configuration
