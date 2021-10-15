// Mocha root hooks for integration tests
// Starts a Hardhat server with Mangrove and related contracts deployed.
//
// NB: We use root hooks instead of global test fixtures to allow sharing state (e.g. provider) with tests.

// Set up hardhat
const hre = require("hardhat");
const hardhatUtils = require("../../hardhat-utils");

const ethers = hre.ethers;

let server; // used to run a localhost server

const host = {
  name: "localhost",
  port: 8546,
};

const awaitTransaction = async (contractTransactionPromise) => {
  let tx = await contractTransactionPromise;
  let txReceipt = await tx.wait();
};

exports.mochaHooks = {
  async beforeAll() {
    this.provider = hre.network.provider;
    // FIXME the hre.network.provider is not a full ethers Provider, e.g. it doesn't have getBalance() and getGasPrice()
    // FIXME we therefore introduce a workaround where tests can construct an appropriate provider themselves from a URL.
    this.providerUrl = `http://${host.name}:${host.port}`;

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
    const testMakerContract = await hre.ethers.getContract("TestMaker");

    await awaitTransaction(
      mgvContract.activate(TokenA.address, TokenB.address, 0, 10, 80000, 20000)
    );
    await awaitTransaction(
      mgvContract.activate(TokenB.address, TokenA.address, 0, 10, 80000, 20000)
    );

    await awaitTransaction(TokenA.mint(account, toWei(10)));
    await awaitTransaction(TokenA.approve(mgvContract.address, toWei(1000)));

    await awaitTransaction(TokenB.mint(account, toWei(10)));
    await awaitTransaction(TokenB.approve(mgvContract.address, toWei(1000)));

    await awaitTransaction(mgvContract["fund()"]({ value: toWei(10) }));
    await awaitTransaction(
      mgvContract["fund(address)"](testMakerContract.address, {
        value: toWei(10),
      })
    );

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
