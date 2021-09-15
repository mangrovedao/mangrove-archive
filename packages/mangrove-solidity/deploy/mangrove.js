module.exports = async (hre) => {
  const deployer = (await hre.getNamedAccounts()).deployer;
  const mgv_dep = await hre.deployments.deploy("Mangrove", {
    from: deployer,
    args: [1 /*gasprice*/, 500000 /*gasmax*/],
    log: true,
  });

  const ta_dep = await hre.deployments.deploy("TokenA", {
    contract: "TestToken",
    from: deployer,
    args: [deployer, "Token A", "A"],
    log: true,
  });

  const tb_dep = await hre.deployments.deploy("TokenB", {
    contract: "TestToken",
    from: deployer,
    args: [deployer, "Token B", "B"],
    log: true,
  });

  await hre.deployments.deploy("TestMaker", {
    from: deployer,
    args: [mgv_dep.address, ta_dep.address, tb_dep.address],
    log: true,
  });

  await hre.deployments.deploy("MgvReader", {
    contract: "MgvReader",
    from: deployer,
    args: [mgv_dep.address],
    log: true,
  });
};
module.exports.tags = ["TestingSetup"];
