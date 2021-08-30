// TODO Find better way of doing this...
function requireFromProjectRoot(pathFromProjectRoot) {
  return require("./../" + pathFromProjectRoot);
}

// Add Polygon environment to Hardhat Runtime Environment
extendEnvironment((hre) => {
  const config = require("config"); // Reads configuration files from /config/

  if (config.has("polygon")) {
    let polygonConfig = config.get("polygon");

    if (!hre.env) {
      hre.env = {};
    }

    hre.env.polygon = {
      network: polygonConfig.network,
      tokens: getConfiguredTokens(polygonConfig, hre),
    };

    const admin = tryGetAdminEnv(polygonConfig, hre);
    if (admin) {
      hre.env.polygon.admin = admin;
    }

    const mangrove = tryGetMangroveEnv(polygonConfig, hre);
    if (mangrove) {
      hre.env.polygon.mgv = mangrove;
    }

    const compound = tryGetCompoundEnv(polygonConfig, hre);
    if (compound) {
      hre.env.polygon.compound = compound;
    }
  }
});

function getConfiguredTokens(polygonConfig, hre) {
  let tokens = {};

  // DAI
  if (polygonConfig.has("tokens.dai")) {
    const daiContract = tryCreateTokenContract(
      "DAI",
      "dai",
      polygonConfig,
      hre
    );
    if (daiContract) {
      tokens.dai = { contract: daiContract };

      const daiConfig = polygonConfig.get("tokens.dai");
      if (daiConfig.has("admin")) {
        tokens.dai.adminAddress = daiConfig.get("admin"); // to mint fresh DAIs
      }
    }
  }

  // WETH
  if (polygonConfig.has("tokens.wEth")) {
    const wEthContract = tryCreateTokenContract(
      "WETH",
      "wEth",
      polygonConfig,
      hre
    );
    if (wEthContract) {
      tokens.wEth = { contract: wEthContract };
    }
  }

  // Compund tokens ????
  // CRDAI
  if (polygonConfig.has("tokens.crDai")) {
    const crDaiContract = tryCreateTokenContract(
      "CRDAI",
      "crDai",
      polygonConfig,
      hre
    );
    if (crDaiContract) {
      tokens.crDai = {
        contract: crDaiContract,
        isCompoundToken: true, // ?????
      };
    }
  }

  // CRWETH
  if (polygonConfig.has("tokens.crWeth")) {
    const crWethContract = tryCreateTokenContract(
      "CRWETH",
      "crWeth",
      polygonConfig,
      hre
    );
    if (crWethContract) {
      tokens.crWeth = {
        contract: crWethContract,
        isCompoundToken: true, // ????
      };
    }
  }

  return tokens;
}

function tryCreateTokenContract(tokenName, configName, polygonConfig, hre) {
  if (!polygonConfig.has(`tokens.${configName}`)) {
    return null;
  }
  const tokenConfig = polygonConfig.get(`tokens.${configName}`);

  if (!tokenConfig.has("address")) {
    console.warn(
      `Config for ${tokenName} does not specify an address. Contract therefore not available.`
    );
    return null;
  }
  const tokenAddress = tokenConfig.get("address");
  if (!tokenConfig.has("abi")) {
    console.warn(
      `Config for ${tokenName} does not specify an abi file. Contract therefore not available.`
    );
    return null;
  }
  const tokenAbi = requireFromProjectRoot(tokenConfig.get("abi"));

  console.info(
    `Polygon token ${tokenName} ABI loaded. Address: ${tokenAddress}`
  );
  return new hre.ethers.Contract(tokenAddress, tokenAbi, hre.ethers.provider);
}

function tryGetAdminEnv(polygonConfig, hre) {
  if (!polygonConfig.has("admin")) {
    return null;
  }
  const adminConfig = polygonConfig.get("admin");
  let admin = {};

  if (adminConfig.has("ChildChainManager")) {
    admin.childChainManager = adminConfig.get("ChildChainManager");
  }

  return admin;
}

function tryGetCompoundEnv(polygonConfig, hre) {
  if (!polygonConfig.has("compound")) {
    return null;
  }
  const compoundConfig = polygonConfig.get("compound");

  if (!compoundConfig.has("unitrollerAddress")) {
    console.warn(
      "Config for Compound does not specify a unitroller address. Compound is therefore not available."
    );
    return null;
  }
  const unitrollerAddress = compoundConfig.get("unitrollerAddress");
  if (!compoundConfig.has("unitrollerAbi")) {
    console.warn(
      `Config for Compound does not specify a unitroller abi file. Compound is therefore not available.`
    );
    return null;
  }
  const compAbi = requireFromProjectRoot(compoundConfig.get("unitrollerAbi"));

  let compound = {
    contract: new hre.ethers.Contract(
      unitrollerAddress,
      compAbi,
      hre.ethers.provider
    ),
  };

  if (compoundConfig.has("whale")) {
    const compoundWhale = compoundConfig.get("whale");
    compound.whale = compoundWhale;
  }

  console.info(
    `Polygon Compound ABI loaded. Unitroller address: ${unitrollerAddress}`
  );
  return compound;
}

function tryGetMangroveEnv(polygonConfig, hre) {
  if (!polygonConfig.has("mangrove")) {
    return null;
  }
  const mangroveConfig = polygonConfig.get("mangrove");
  let mangrove = {};

  if (!mangroveConfig.has("address")) {
    console.warn(
      "Config for Mangrove does not specify an address. Contract therefore not available."
    );
    return null;
  }
  const mangroveAddress = mangroveConfig.get("address");
  if (mangroveConfig.has("abi")) {
    console.info(
      "Config for Mangrove specifies an abi file, so using that instead of artifacts in .build"
    );
    const mangroveAbi = requireFromProjectRoot(mangroveConfig.get("abi"));
    mangrove.contract = new hre.ethers.Contract(
      mangroveAddress,
      mangroveAbi,
      hre.ethers.provider
    );
  } else {
    // NB (Espen): Hardhat launches tasks without awaiting, so async loading of env makes stuff difficult.
    //             It's not clear to me how to support loading the ABI from .build without async
    // const mangroveContractFactory = await hre.ethers.getContractFactory("Mangrove");
    // mangrove.contract = mangroveContractFactory.attach(mangroveAddress);
    console.warn(
      "Config for Mangrove does not specify an abi file. Mangrove env is therefore not available. But you can deploy it with 'deployOnEthereum()'."
    );
  }

  // TODO Can we read the active markets?

  console.info(`Polygon Mangrove ABI loaded. Address: ${mangroveAddress}`);
  return mangrove;
}
