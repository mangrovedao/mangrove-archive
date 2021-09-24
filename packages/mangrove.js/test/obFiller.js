const hre = require("hardhat");
const helpers = require("./helpers");
const main = async () => {
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

  console.log(provider);
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
  console.log("user", user);

  const signer2 = provider.getSigner();
  console.log("user2", await signer2.getAddress());

  // const signer = (await hre.ethers.getSigners())[0];
  await TokenA.mint(user, toWei(10));
  await TokenA.approve(mgvContract.address, toWei(1000));

  await TokenB.mint(user, toWei(10));
  await TokenB.approve(mgvContract.address, toWei(1000));

  await mgvContract["fund()"]({ value: toWei(10) });

  const newOffer = (base, quote, { wants, gives, gasreq, gasprice }) => {
    return mgv.contract.newOffer(
      base,
      quote,
      helpers.toWei(wants),
      helpers.toWei(gives),
      gasreq || 10000,
      gasprice || 1,
      0
    );
  };

  const retractOffer = (base, quote, offerId) => {
    return mgv.contract.retractOffer(base, quote, offerId, true);
  };

  const between = (a, b) => a + Math.random() * (b - a);
  const market = await mgv.market({ base: "TokenA", quote: "TokenB" });

  const pushOffer = async () => {
    const book = await market.book();
    const buffer = book.asks.length > 30 ? 5000 : 0;
    console.log("asks length", book.asks.length);

    const timeoutId = setTimeout(() => {
      console.log("pushing offer");
      newOffer(market.base.address, market.quote.address, {
        wants: 1,
        gives: 1,
      });
      pushOffer();
    }, between(1000 + buffer, 3000 + buffer));
  };

  const pullOffer = async () => {
    const book = await market.book();
    console.log(
      "ids",
      book.asks.map((o) => o.id)
    );
    if (book.asks.length !== 0) {
      const offer = book.asks.shift();
      await retractOffer(market.base.address, market.quote.address, offer.id);
    }
    const timeoutId = setTimeout(() => {
      pullOffer();
    }, between(2000, 4000));
  };

  pushOffer();
  pullOffer();
};

main().catch((e) => console.error(e));
