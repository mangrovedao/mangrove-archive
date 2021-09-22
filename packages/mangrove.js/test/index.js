// Mangrove Tests

// To run all tests: `npm test`
// To run a single file's tests: `npm test -- -g './src/eth.ts'`
// To run a single test: `npm test -- -g 'eth.getBalance'`

// Set up hardhat
const { TASK_NODE_CREATE_SERVER } = require("hardhat/builtin-tasks/task-names");
const hre = require("hardhat");
const ethers = hre.ethers;
let jsonRpcServer; // used to run a localhost fork of mainnet

// Source Files
const { Mangrove } = require("../src/index.ts");
const providerUrl = "http://localhost:8545";
const _eth = require("../src/eth.ts");

const tests = {
  market: require("./market.test.js"),
};

// const mnemonic = hre.config.networks.hardhat.accounts.mnemonic;

const mnemonic = hre.network.config.accounts.mnemonic;
const addresses = [];
const privateKeys = [];
for (let i = 0; i < 20; i++) {
  const wallet = new ethers.Wallet.fromMnemonic(
    mnemonic,
    `m/44'/60'/0'/0/${i}`
  );
  addresses.push(wallet.address);
  privateKeys.push(wallet._signingKey().privateKey);
}

let acc = [addresses, privateKeys]; // Unlocked accounts with test ETH
let snapshot_id = null;

// Main test suite
describe("mangrove.js", function () {
  before(async () => {
    console.log("Running a hardhat instance...");

    jsonRpcServer = await hre.run(TASK_NODE_CREATE_SERVER, {
      hostname: "localhost",
      port: 8545,
      provider: hre.network.provider,
    });

    await jsonRpcServer.listen();

    // await hre.network.provider.request({
    //   method: "hardhat_reset",
    //   params: [],
    // });

    const toWei = (v, u = "ether") => ethers.utils.parseUnits(v.toString(), u);

    const deployments = await hre.deployments.run("TestingSetup");

    const mgvContract = await hre.ethers.getContract("Mangrove");
    const mgvReader = await hre.ethers.getContract("MgvReader");
    const TokenA = await hre.ethers.getContract("TokenA");
    const TokenB = await hre.ethers.getContract("TokenB");

    await mgvContract.activate(
      TokenA.address,
      TokenB.address,
      0,
      10,
      80000,
      20000
    );
    await mgvContract.activate(
      TokenB.address,
      TokenA.address,
      0,
      10,
      80000,
      20000
    );

    const signer = (await hre.ethers.getSigners())[0];
    await TokenB.mint(signer.address, toWei(10));
    await TokenA.mint(signer.address, toWei(10));

    await mgvContract["fund()"]({ value: toWei(10) });

    // blackbox discovery of network name that will be used during tests
    const provider = _eth._createProvider({
      provider: "http://localhost:8545",
    });
    const network = await _eth.getProviderNetwork(provider);

    Mangrove.setAddress("Mangrove", mgvContract.address, network.name);
    Mangrove.setAddress("TokenA", TokenA.address, network.name);
    Mangrove.setAddress("TokenB", TokenB.address, network.name);
    Mangrove.setAddress(
      "MgvReader",
      deployments.MgvReader.address,
      network.name
    );
    await Mangrove.cacheDecimals("TokenA", provider);
    await Mangrove.cacheDecimals("TokenB", provider);

    await snapshot();
  });

  beforeEach(async () => {
    await revert();
    await snapshot();
  });

  after(async () => {
    await jsonRpcServer.close();
  });

  for (const [name, test] of Object.entries(tests)) {
    describe(name, test.bind(this, acc));
  }
});

async function snapshot() {
  const res = await hre.network.provider.request({
    method: "evm_snapshot",
    params: [],
  });
  snapshot_id = res;
  //console.log("snapshot recorded with id",snapshot_id);
}

async function revert() {
  //console.log("reverting to...",snapshot_id);
  await hre.network.provider.request({
    method: "evm_revert",
    params: [snapshot_id],
  });
}
