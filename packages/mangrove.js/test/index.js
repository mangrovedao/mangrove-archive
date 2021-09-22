// Mangrove Tests

// To run all tests: `npm test`
// To run a single file's tests: `npm test -- -g './src/eth.ts'`
// To run a single test: `npm test -- -g 'eth.getBalance'`

// Set up hardhat
const hre = require("hardhat");
const helpers = require("./helpers");
const ethers = hre.ethers;
let server; // used to run a localhost server

// Source Files
const { Mangrove } = require("../src");

const host = {
  name: "localhost",
  port: 8546,
};
const _eth = require("../src/eth.ts");
// const { start } = require("repl");

const tests = {
  market: require("./market.test.js"),
};

let snapshot_id = null;

// Main test suite
describe("mangrove.js", function () {
  before(async () => {
    console.log("Running a hardhat instance...");
    server = await helpers.hreServer({
      hostname: host.name,
      port: host.port,
      provider: hre.network.provider,
    });

    await hre.network.provider.request({
      method: "hardhat_reset",
      params: [],
    });

    // blackbox discovery of network name that will be used during tests
    const signer = _eth._createSigner({
      provider: `http://${host.name}:${host.port}`,
    });

    const account = signer.getAddress();

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

    // const signer = (await hre.ethers.getSigners())[0];
    await TokenA.mint(account, toWei(10));
    await TokenA.approve(mgvContract.address, toWei(1000));

    await TokenB.mint(account, toWei(10));
    await TokenB.approve(mgvContract.address, toWei(1000));

    await mgvContract["fund()"]({ value: toWei(10) });

    const network = await _eth.getProviderNetwork(signer.provider);

    Mangrove.setAddress("Mangrove", mgvContract.address, network.name);
    Mangrove.setAddress("TokenA", TokenA.address, network.name);
    Mangrove.setAddress("TokenB", TokenB.address, network.name);
    Mangrove.setAddress(
      "MgvReader",
      deployments.MgvReader.address,
      network.name
    );
    await Mangrove.cacheDecimals("TokenA", signer.provider);
    await Mangrove.cacheDecimals("TokenB", signer.provider);

    await snapshot();
  });

  beforeEach(async () => {
    await revert();
    await snapshot();
  });

  after(async () => {
    if (server) {
      await server.close();
    }
  });

  for (const [name, test] of Object.entries(tests)) {
    describe(name, test.bind(this));
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
