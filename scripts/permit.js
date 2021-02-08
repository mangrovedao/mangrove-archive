// /* Test Dex's permit functionality */
//
//
// ! WARNING ! Currently nonfunctional, waiting for hardhat to implement eth_signTypedData_v4.
//
//
// To watch:
// https://github.com/nomiclabs/hardhat/issues/1199
//
// Run with
//   npx hardhat run scripts/deploy.js
// possibly prefixed with
//   HARDHAT_NETWORK=<network name from hardhat.config>
// if you want the deploy to persist somewhere
async function main() {
  const ethers = hre.ethers;

  const DexLib = await ethers.getContractFactory("DexLib");
  const dexLib = await DexLib.deploy();

  const DexSetup = await ethers.getContractFactory("DexSetup", {
    libraries: { DexLib: dexLib.address },
  });
  const dexSetup = await DexSetup.deploy();

  const TokenSetup = await ethers.getContractFactory("TokenSetup");
  const tokenSetup = await TokenSetup.deploy();
  //const Dex = await ethers.getContractFactory("FMD", {
  //libraries: { DexLib: dexLib.address },
  //});

  const Permit = await ethers.getContractFactory("PermitHelper", {
    libraries: {
      DexSetup: dexSetup.address,
      TokenSetup: tokenSetup.address,
    },
  });

  const permit = await Permit.deploy();

  const dexAddress = await permit.dexAddress();
  const baseAddress = await permit.baseAddress();
  const quoteAddress = await permit.quoteAddress();

  //const dex = Dex.attach(dexAddress);
  const TestToken = await ethers.getContractFactory("TestToken");
  const quote = TestToken.attach(quoteAddress);
  await quote.approve(dexAddress, ethers.utils.parseUnits("1", "ether"));

  /* hardhat ethers wrapper does not expose signTypedData so we get the raw object */
  /* see https://github.com/nomiclabs/hardhat/issues/1108 */
  const owner = await ethers.provider.getSigner();

  // Follow https://eips.ethereum.org/EIPS/eip-2612
  const domain = {
    name: "FMD",
    version: "1",
    chainId: 31337, // hardhat chainid
    verifyingContract: dexAddress,
  };

  const types = {
    Permit: [
      { name: "base", type: "address" },
      { name: "quote", type: "address" },
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  const value = ethers.utils.parseUnits("2", "ether");
  const deadline = 100;

  // The data to sign
  const data = {
    base: baseAddress,
    quote: quoteAddress,
    owner: await owner.getAddress(),
    spender: permit.address,
    value: value,
    nonce: 0,
    deadline: deadline,
  };

  console.dir(data);
  console.dir(dexAddress);

  /* hardhat does not yet implement eth_signTypedData_v4, which is what ethers.js calls */
  /* see https://github.com/nomiclabs/hardhat/pull/1189 */
  const rawSignature = await owner._signTypedData(domain, types, data);

  const signature = ethers.utils.splitSignature(rawSignature);

  permit.applyPermit(value, deadline, signature.v, signature.r, signature.s);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
