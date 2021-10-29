const hre = require("hardhat");
const helpers = require("../util/helpers");
const hardhatUtils = require("@giry/hardhat-mangrove/hardhat-utils");
const seed =
  Math.random().toString(36).substring(2, 15) +
  Math.random().toString(36).substring(2, 15);
console.log(`random seed: ${seed}`);
const rng = require("seedrandom")(seed);

const main = async () => {
  console.log("Mnemonic:");
  console.log(hre.config.networks.hardhat.accounts.mnemonic);
  console.log("");
  const { Mangrove } = require("../../src");

  const host = {
    name: "localhost",
    port: 8546,
  };

  const server = await hardhatUtils.hreServer({
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

  // const deployer = (await hre.getNamedAccounts()).deployer;
  const deployer = (await hre.ethers.getSigners())[1];
  const deployments = await hre.deployments.run("TestingSetup");
  // const params = await (require("@giry/mangrove-solidity/lib/testDeploymentParams")());

  const user = (await hre.ethers.getSigners())[0];
  // const signer = (await hre.ethers.getSigners())[1];
  // const user = await signer.getAddress();

  // console.log(await hre.deployments.deterministic("Mangrove",{
  //   from: deployer,
  //   args: [1 /*gasprice*/, 500000 /*gasmax*/],
  // }));
  const mgv = await Mangrove.connect({
    signer: deployer,
    provider: `http://${host.name}:${host.port}`,
  });
  const mgvContract = await hre.ethers.getContract("Mangrove", deployer);
  const mgvReader = await hre.ethers.getContract("MgvReader", deployer);
  // const TokenA = await hre.ethers.getContract("TokenA");
  // const TokenB = await hre.ethers.getContract("TokenB");

  // Setup Mangrove to use MgvOracle as oracle
  const mgvOracle = await hre.ethers.getContract("MgvOracle", deployer);
  await mgvContract.setMonitor(mgvOracle.address);
  await mgvContract.setUseOracle(true);
  await mgvContract.setNotify(true);

  const gasUpdater = (await hre.getNamedAccounts()).gasUpdater;
  await mgvOracle.setMutator(gasUpdater);

  const activate = (base, quote) => {
    return mgvContract.activate(base, quote, 0, 10, 80000, 20000);
  };

  const userA = await user.getAddress();
  console.log("user", userA);
  const deployerA = await deployer.getAddress();
  console.log("deployer", deployerA);

  const approve = (tkn) => {
    tkn.contract.mint(userA, mgv.toUnits(tkn.amount, tkn.name));
  };

  // await activate(TokenA.address,TokenB.address);
  // await activate(TokenB.address,TokenA.address);

  const tkns = [
    { name: "WETH", amount: 1000 },
    { name: "DAI", amount: 10_000 },
    { name: "USDC", amount: 10_000 },
  ];

  for (const t of tkns)
    t.contract = await hre.ethers.getContract(t.name, deployer);

  for (const tkn1 of tkns) {
    await approve(tkn1);
    for (const tkn2 of tkns) {
      if (tkn1 !== tkn2) {
        await activate(tkn1.contract.address, tkn2.contract.address);
      }
    }
  }

  const toWei = (v, u = "ether") =>
    hre.ethers.utils.parseUnits(v.toString(), u);
  console.log("Deployer");
  console.log(await deployer.getAddress());
  console.log();
  console.log("User");
  console.log(userA);
  console.log("");

  // const signer2 = provider.getSigner();
  // console.log("user2", await signer2.getAddress());

  // const signer = (await hre.ethers.getSigners())[0];
  // await TokenA.mint(user, mgv.toUnits("TokenA", 1000));
  // await TokenA.approve(mgvContract.address, toWei(1000000));

  // await TokenB.mint(user, mgv.toUnits("TokenB", 1000));
  // await TokenB.approve(mgvContract.address, toWei(1000000));

  await mgvContract["fund()"]({ value: toWei(100) });

  const newOffer = async (base, quote, { wants, gives, gasreq, gasprice }) => {
    try {
      await mgv.contract.newOffer(
        base,
        quote,
        helpers.toWei(wants),
        helpers.toWei(gives),
        gasreq || 100000,
        gasprice || 1,
        0
      );
    } catch (e) {
      console.log(e);
      console.warn(
        `Posting offer failed - base=${base}, quote=${quote}, wants=${wants}, gives=${gives}, gasreq=${gasreq}, gasprice=${gasprice}`
      );
    }
  };

  const retractOffer = async (base, quote, offerId) => {
    const estimate = await mgv.contract.estimateGas.retractOffer(
      base,
      quote,
      offerId,
      true
    );
    const newEstimate = Math.round(estimate.toNumber() * 1.3);
    const resp = await mgv.contract.retractOffer(base, quote, offerId, true, {
      gasLimit: newEstimate,
    });
    const receipt = await resp.wait(0);
    if (!estimate.eq(receipt.gasUsed)) {
      console.log(
        "estimate != used:",
        estimate.toNumber(),
        receipt.gasUsed.toNumber()
      );
    }
    return mgv.contract.retractOffer(base, quote, offerId, true);
  };

  const between = (a, b) => a + rng() * (b - a);

  for (const t of tkns) {
    console.log(`${t.name} (${mgv.getDecimals(t.name)} decimals)`);
    console.log(t.contract.address);
    console.log("");
  }

  const WethDai = await mgv.market({ base: "WETH", quote: "DAI" });
  const WethUsdc = await mgv.market({ base: "WETH", quote: "USDC" });
  const DaiUsdc = await mgv.market({ base: "DAI", quote: "USDC" });

  const markets = [WethDai, WethUsdc, DaiUsdc];

  // console.log(`Token B (${mgv.getDecimals("TokenB")} decimals`);
  // console.log(market.quote.address);
  // console.log();

  console.log("Orderbook filler is now running.");

  const pushOffer = async (market, ba /*bids|asks*/) => {
    let base = "base",
      quote = "quote";
    if (ba === "bids") [base, quote] = [quote, base];
    const book = await market.book();
    // console.log(book,ba,book[ba]);
    const buffer = book[ba].length > 30 ? 5000 : 0;
    // console.log(`${ba} length`, book[ba].length);

    setTimeout(async () => {
      // console.log(`pushing offer to ${ba}`);
      const wants = 1 + between(0, 3);
      const gives = wants * between(1.001, 4);
      await newOffer(market[base].address, market[quote].address, {
        wants,
        gives,
      });
      pushOffer(market, ba);
    }, between(1000 + buffer, 3000 + buffer));
  };

  const pullOffer = async (market, ba) => {
    let base = "base",
      quote = "quote";
    if (ba === "bids") [base, quote] = [quote, base];
    const book = await market.book();
    // console.log(
    //   `${ba} ids`,
    //   book[ba].map((o) => o.id)
    // );

    if (book[ba].length !== 0) {
      // const offer = book[ba].shift();
      const pulledIndex = Math.floor(rng() * book[ba].length);
      const offer = book[ba][pulledIndex];
      await retractOffer(market[base].address, market[quote].address, offer.id);
    }
    setTimeout(() => {
      pullOffer(market, ba);
    }, between(2000, 4000));
  };

  // setTimeout(async () => {
  //   const bla = await market.buy({wants:3,gives:4});
  //   console.log(bla);
  // // console.log(bla);
  // // console.log((await bla.wait()).events);
  // },5000);

  for (const market of markets) {
    pushOffer(market, "asks");
    pushOffer(market, "bids");
    pullOffer(market, "asks");
    pullOffer(market, "bids");
  }
};

main().catch((e) => console.error(e));
