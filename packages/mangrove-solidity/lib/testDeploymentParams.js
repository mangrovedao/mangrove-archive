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

  const makeToken = (name, symbol) => {
    return {
      name: name,
      options: {
        contract: "TestToken",
        from: deployer,
        args: [deployer, name, symbol],
      },
    };
  };

  const tokenA = await withAddress(makeToken("TokenA", "A"));
  const tokenB = await withAddress(makeToken("TokenB", "B"));

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

  return [mangrove, tokenA, tokenB, testMaker, mgvReader];
};
