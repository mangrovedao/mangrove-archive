/* TODO: Need hardhat temporarily to get signer */
const hre = require("hardhat");
const ethers = hre.ethers;
/* --- */

/* --- TODO: The following is temp code that uses hardhat to get 
             a signer via a mnemonic; should get signer externally */

export function getSigner(){
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
    return privateKeys[0];
}