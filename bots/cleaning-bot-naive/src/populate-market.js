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

// TODO No API for activating markets? Using contract directly for now
const main = async () => {
    // const mgv = await Mangrove.connect("http://127.0.0.1:8545", {privateKey: signer.privateKey});
    const mgv = await Mangrove.connect(
        "http://127.0.0.1:8545", // TODO move connection string / network name to configuration
        {
          privateKey: privateKeys[0],
        }    
        );
    
    const baseTokenName = "TokenA";
    const quoteTokenName = "TokenB";
  
    await mgv.contract.activate(
        mgv.getAddress(baseTokenName),
        mgv.getAddress(quoteTokenName),
        0,
        10,
        80000,
        20000
    );
}

main();