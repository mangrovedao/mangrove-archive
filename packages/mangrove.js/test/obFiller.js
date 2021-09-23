const hre = require("hardhat");
const helpers = require("./helpers");
const main = async () => {
  console.log("Mnemonic:");
  console.log(hre.config.networks.hardhat.accounts.mnemonic);
  console.log("");
  const { Mangrove } = require("../src");

  const host = {
    name: "localhost",
    port: 8546,
  };

  const server = await helpers.hreServer({
    hostname: host.name,
    port: host.port,
    provider: hre.network.provider,
  });

  const provider = new hre.ethers.providers.JsonRpcProvider(
    `http://${host.name}:${host.port}`
  );

  console.log("RPC node");
  console.log(`http://${host.name}:${host.port}`);
  console.log("");

  // console.log(provider);
  // await provider.send(
  //   "hardhat_reset",
  //   [],
  // );

  const deployer = (await hre.getNamedAccounts()).deployer;
  const deployments = await hre.deployments.run("TestingSetup");

  // console.log(await hre.deployments.deterministic("Mangrove",{
  //   from: deployer,
  //   args: [1 /*gasprice*/, 500000 /*gasmax*/],
  // }));
  const mgv = await Mangrove.connect(`http://${host.name}:${host.port}`);
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

  const toWei = (v, u = "ether") =>
    hre.ethers.utils.parseUnits(v.toString(), u);
  const signer = (await hre.ethers.getSigners())[0];
  const user = await signer.getAddress();
  console.log("User/admin");
  console.log(user);
  console.log("");

  const signer2 = provider.getSigner();
  // console.log("user2", await signer2.getAddress());

  // const signer = (await hre.ethers.getSigners())[0];
  await TokenA.mint(user, toWei(10000));
  await TokenA.approve(mgvContract.address, toWei(1000000));

  await TokenB.mint(user, toWei(10000));
  await TokenB.approve(mgvContract.address, toWei(1000000));

  await mgvContract["fund()"]({ value: toWei(100) });

  const newOffer = (base, quote, { wants, gives, gasreq, gasprice }) => {
    return mgv.contract.newOffer(
      base,
      quote,
      helpers.toWei(wants),
      helpers.toWei(gives),
      gasreq || 100000,
      gasprice || 1,
      0
    );
  };

  const retractOffer = (base, quote, offerId) => {
    return mgv.contract.retractOffer(base, quote, offerId, true);
  };

  const between = (a, b) => a + Math.random() * (b - a);
  const market = await mgv.market({ base: "TokenA", quote: "TokenB" });

  const pushOffer = async (ba /*bids|asks*/) => {
    let base = "base",
      quote = "quote";
    if (ba === "bids") [base, quote] = [quote, base];
    const book = await market.book();
    // console.log(book,ba,book[ba]);
    const buffer = book[ba].length > 30 ? 5000 : 0;
    // console.log(`${ba} length`, book[ba].length);

    setTimeout(() => {
      // console.log(`pushing offer to ${ba}`);
      const wants = 1 + between(0, 3);
      const gives = wants * between(1.001, 4);
      newOffer(market[base].address, market[quote].address, { wants, gives });
      pushOffer(ba);
    }, between(1000 + buffer, 3000 + buffer));
  };

  const pullOffer = async (ba) => {
    let base = "base",
      quote = "quote";
    if (ba === "bids") [base, quote] = [quote, base];
    const book = await market.book();
    // console.log(
    //   `${ba} ids`,
    //   book[ba].map((o) => o.id)
    // );
    if (book[ba].length !== 0) {
      const offer = book[ba].shift();
      await retractOffer(market[base].address, market[quote].address, offer.id);
    }
    setTimeout(() => {
      pullOffer(ba);
    }, between(2000, 4000));
  };

  pushOffer("asks");
  pullOffer("asks");
  pushOffer("bids");
  pullOffer("bids");
};

main().catch((e) => console.error(e));
