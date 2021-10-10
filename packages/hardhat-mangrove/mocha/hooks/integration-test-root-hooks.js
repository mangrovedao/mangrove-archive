// Mocha root hooks for integration tests
// Starts a Hardhat server with Mangrove and related contracts deployed.
//
// NB: We use root hooks instead of global test fixtures to allow sharing state (e.g. provider) with tests.

// FIXME Move to mangrove-solidity or separate library

// Set up hardhat
const hre = require("hardhat");
const hardhatUtils = require("../../hardhat-utils");

const ethers = hre.ethers;

let server; // used to run a localhost server

const host = {
  name: "localhost",
  port: 8546,
};

exports.mochaHooks = {
  async beforeAll() {
    this.provider = hre.network.provider;

    console.log("Running a Hardhat instance...");
    server = await hardhatUtils.hreServer({
      hostname: host.name,
      port: host.port,
      provider: this.provider,
    });

    await hre.network.provider.request({
      method: "hardhat_reset",
      params: [],
    });

    const signer = (await ethers.getSigners())[0];

    const account = await signer.getAddress();

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

    await TokenA.mint(account, toWei(10));
    await TokenA.approve(mgvContract.address, toWei(1000));

    await TokenB.mint(account, toWei(10));
    await TokenB.approve(mgvContract.address, toWei(1000));

    await mgvContract["fund()"]({ value: toWei(10) });

    await snapshot();
  },

  async beforeEach() {
    await revert();
    await snapshot();
  },

  async afterAll() {
    if (server) {
      await server.close();
    }
  },
};

let snapshot_id = null;

async function snapshot() {
  const res = await hre.network.provider.request({
    method: "evm_snapshot",
    params: [],
  });
  snapshot_id = res;
}

async function revert() {
  await hre.network.provider.request({
    method: "evm_revert",
    params: [snapshot_id],
  });
}
