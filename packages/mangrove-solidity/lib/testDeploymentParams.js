const hre = require("hardhat");

module.exports = async () => {
  const deployer = (await hre.getNamedAccounts()).deployer;

  const withAddress = async (params) => {
    const { address } = await hre.deployments.deterministic(
      params.name,
      params.options
    );
    params.address = address;
    return params;
  };

  const mangrove = await withAddress({
    name: "Mangrove",
    options: {
      from: deployer,
      args: [deployer /* governance */, 1 /*gasprice*/, 500000 /*gasmax*/],
    },
  });

  const makeToken = (tokenName, symbol, decimals = 18) => {
    return {
      name: symbol,
      token: true,
      options: {
        contract: "TestTokenWithDecimals",
        from: deployer,
        args: [deployer, tokenName, symbol, decimals],
      },
    };
  };

  const tokenA = await withAddress(makeToken("Token A", "TokenA"));
  const tokenB = await withAddress(makeToken("Token B", "TokenB"));
  const Dai = await withAddress(makeToken("Dai Stablecoin", "DAI", 18));
  const Usdc = await withAddress(makeToken("USDC", "USDC", 6));
  const Weth = await withAddress(makeToken("WETH", "WETH", 18));

  const testMaker = await withAddress({
    name: "TestMaker",
    options: {
      from: deployer,
      args: [mangrove.address, tokenA.address, tokenB.address],
    },
  });

  const mgvReader = await withAddress({
    name: "MgvReader",
    options: {
      from: deployer,
      args: [mangrove.address],
    },
  });

  const mgvCleaner = await withAddress({
    name: "MgvCleaner",
    options: {
      from: deployer,
      args: [mangrove.address],
    },
  });

  const mgvOracle = await withAddress({
    name: "MgvOracle",
    options: {
      from: deployer,
      args: [mangrove.address],
    },
  });

  return [
    mangrove,
    tokenA,
    tokenB,
    Dai,
    Usdc,
    Weth,
    testMaker,
    mgvReader,
    mgvCleaner,
    mgvOracle,
  ];
};
