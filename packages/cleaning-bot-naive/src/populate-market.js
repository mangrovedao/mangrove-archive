const hre = require("hardhat");
const ethers = hre.ethers;

// const { Mangrove } = require("../../../mangrove.js/src/index.ts");
const { Mangrove } = require("../../../mangrove.js/dist/nodejs/mangrove");

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

const toWei = (v, u = "ether") => ethers.utils.parseUnits(v.toString(), u);

// TODO No API for activating markets? Using contract directly for now
const main = async () => {
    // const mgv = await Mangrove.connect("http://127.0.0.1:8545", {privateKey: signer.privateKey});
    const mgv = await Mangrove.connect(
        "http://127.0.0.1:8545", // TODO move connection string / network name to configuration
        {
          privateKey: privateKeys[0],
        }    
        );

    const tokenAbi = require("../../../build/cache/solpp-generated-contracts/Tests/Agents/TestToken.sol/TestToken.json").abi;
    const TokenA = new hre.ethers.Contract(mgv.getAddress("TokenA"), tokenAbi, mgv._provider);
    const TokenB = new hre.ethers.Contract(mgv.getAddress("TokenB"), tokenAbi, mgv._provider);
      
    await mgv.contract.activate(
        TokenA.address,
        TokenB.address,
        0,
        10,
        80000,
        20000
      );
    await mgv.contract.activate(
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

    await mgv.contract["fund()"]({ value: toWei(10) });
  }

main();