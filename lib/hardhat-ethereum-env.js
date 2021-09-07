// TODO Find better way of doing this...
function requireFromProjectRoot(pathFromProjectRoot) {
  return require("./../" + pathFromProjectRoot);
}

// Add Ethereum environment to Hardhat Runtime Environment
extendEnvironment((hre) => {
  const config = require("config"); // Reads configuration files from /config/

  if (config.has("ethereum")) {
    let ethereumConfig = config.get("ethereum");

    if (!hre.env) {
      hre.env = {};
    }

    hre.env.ethereum = {
      network: ethereumConfig.network,
      tokens: getConfiguredTokens(ethereumConfig, hre),
    };

    const mangrove = tryGetMangroveEnv(ethereumConfig, hre);
    if (mangrove) {
      hre.env.ethereum.mgv = mangrove;
    }

    const compound = tryGetCompoundEnv(ethereumConfig, hre);
    if (compound) {
      hre.env.ethereum.compound = compound;
    }

    const aave = tryGetAaveEnv(ethereumConfig, hre);
    if (aave) {
      hre.env.ethereum.aave = aave;
    }
  }
});

function getConfiguredTokens(ethereumConfig, hre) {
  let tokens = {};

  // DAI
  if (ethereumConfig.has("tokens.dai")) {
    const daiContract = tryCreateTokenContract(
      "DAI",
      "dai",
      ethereumConfig,
      hre
    );
    if (daiContract) {
      tokens.dai = { contract: daiContract };

      const daiConfig = ethereumConfig.get("tokens.dai");
      if (daiConfig.has("admin")) {
        tokens.dai.adminAddress = daiConfig.get("admin"); // to mint fresh DAIs
      }
    }
  }

  // WETH
  if (ethereumConfig.has("tokens.wEth")) {
    const wEthContract = tryCreateTokenContract(
      "WETH",
      "wEth",
      ethereumConfig,
      hre
    );
    if (wEthContract) {
      tokens.wEth = { contract: wEthContract };
    }
  }

  // Compound tokens
  // CDAI
  if (ethereumConfig.has("tokens.cDai")) {
    const cDaiContract = tryCreateTokenContract(
      "CDAI",
      "cDai",
      ethereumConfig,
      hre
    );
    if (cDaiContract) {
      tokens.cDai = {
        contract: cDaiContract,
        isCompoundToken: true,
      };
    }
  }

  // CETH
  if (ethereumConfig.has("tokens.cEth")) {
    const cEthContract = tryCreateTokenContract(
      "CETH",
      "cEth",
      ethereumConfig,
      hre
    );
    if (cEthContract) {
      tokens.cEth = {
        contract: cEthContract,
        isCompoundToken: true,
      };
    }
  }

  return tokens;
}

function tryCreateTokenContract(tokenName, configName, ethereumConfig, hre) {
  if (!ethereumConfig.has(`tokens.${configName}`)) {
    return null;
  }
  const tokenConfig = ethereumConfig.get(`tokens.${configName}`);

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
    `Ethereum token ${tokenName} ABI loaded. Address: ${tokenAddress}`
  );
  return new hre.ethers.Contract(tokenAddress, tokenAbi, hre.ethers.provider);
}

function tryGetCompoundEnv(ethereumConfig, hre) {
  if (!ethereumConfig.has("compound")) {
    return null;
  }
  let compoundConfig = ethereumConfig.get("compound");

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
    `Ethereum Compound ABI loaded. Unitroller address: ${unitrollerAddress}`
  );
  return compound;
}

function tryGetAaveEnv(ethereumConfig, hre) {
  if (!ethereumConfig.has("aave")) {
    return null;
  }
  let aaveConfig = ethereumConfig.get("aave");

  if (!aaveConfig.has("addressesProvider")) {
    console.warn(
      "Config for Aave does not specify an address provider. Aave is therefore not available."
    );
    return null;
  }
  const addressProviderAddress = aaveConfig.get("addressProvider");
  if (!compoundConfig.has("addressProvider")) {
    console.warn(
      `Config for Aave does not specify a unitroller abi file. Compound is therefore not available.`
    );
    return null;
  }
  const addressProviderAbi = requireFromProjectRoot(aaveConfig.get("addressProviderAbi"));

  let aave = {
    contract: new hre.ethers.Contract(
      addressProviderAddress,
      addressProviderAbi,
      hre.ethers.provider
    ),
  };

  console.info(
    `Ethereum Aave ABI loaded. Address provider is at: ${addressProviderAddress}`
  );
  return aave;
}

function tryGetMangroveEnv(ethereumConfig, hre) {
  if (!ethereumConfig.has("mangrove")) {
    console.warn("Mangrove is not pre deployed");
    return null;
  }
  mangroveConfig = ethereumConfig.get("mangrove");
  mangrove = {};

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

  console.info(`Ethereum Mangrove ABI loaded. Address: ${mangroveAddress}`);
  return mangrove;
}
