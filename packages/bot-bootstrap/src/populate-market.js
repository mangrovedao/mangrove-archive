const hre = require("hardhat");
const ethers = hre.ethers;

const lc = require("@giry/mangrove-solidity/lib/libcommon.js");

/* This script sets up a simple Mangrove market:
 *
 * - Funds a MM account:
 *   - Adds ETH to the account
 *   - Mints tokens of type TokenA and TokenB
 * - Activates market (TokenA, TokenB)
 * - Posts offer
 */

const { Mangrove } = require("@giry/mangrove-js");

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

    const tokenAbi = require("@giry/mangrove-solidity/cache/solpp-generated-contracts/Tests/Agents/TestToken.sol/TestToken.json").abi;
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