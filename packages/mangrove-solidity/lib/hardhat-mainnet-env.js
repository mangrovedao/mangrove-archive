// TODO Find better way of doing this...
function requireFromProjectRoot(pathFromProjectRoot) {
  return require("./../" + pathFromProjectRoot);
}

// Add Ethereum environment to Hardhat Runtime Environment
extendEnvironment((hre) => {
  const config = require("config"); // Reads configuration files from /config/
  let mainnetConfig;
  let networkName;

  
  if (config.has("ethereum")) {
    mainnetConfig = config.get("ethereum");
    networkName = "ethereum"; 
  }

  if (config.has("polygon")) {
    mainnetConfig = config.get("polygon");
    networkName = "polygon";
  }

  // if no network name is defined, then one is not forking mainnet
  if(!networkName){
    return;
  }

  if (!hre.env) {
    hre.env = {};
  }
    
  hre.env.mainnet = {
    network: mainnetConfig.network,
    name : networkName,
    tokens: getConfiguredTokens(mainnetConfig, networkName, hre),
    abis: getExtraAbis(mainnetConfig)
  };

  const childChainManager = getChildChainManager(mainnetConfig);
  if (childChainManager) {
    hre.env.mainnet.childChainManager = childChainManager;
  }

  const mangrove = tryGetMangroveEnv(mainnetConfig, networkName, hre);
  if (mangrove) {
    hre.env.mainnet.mgv = mangrove;
  }

  const compound = tryGetCompoundEnv(mainnetConfig, networkName, hre);
  if (compound) {
    hre.env.mainnet.compound = compound;
  }

  const aave = tryGetAaveEnv(mainnetConfig, networkName, hre);
  if (aave) {
    hre.env.mainnet.aave = aave;
  }
});

function getChildChainManager(mainnetConfig) {
  if (mainnetConfig.has("ChildChainManager")) {
    return (mainnetConfig.get("ChildChainManager"));
  }
}

function getExtraAbis(mainnetConfig) {
  let abis = {};
  if (mainnetConfig.has("extraAbis")) {
    abis.stableDebtToken = requireFromProjectRoot(mainnetConfig.get("extraAbis.stableDebtToken"));
    abis.variableDebtToken = requireFromProjectRoot(mainnetConfig.get("extraAbis.variableDebtToken"));
    abis.aToken = requireFromProjectRoot(mainnetConfig.get("extraAbis.aToken"));
  }
  return abis;
}

function getConfiguredTokens(mainnetConfig, networkName, hre) {
  let tokens = {};

  if(!mainnetConfig) {
    console.warn (`No network configuration was loaded, cannot fork ${networkName} mainnet`);
    return;
  }

  // DAI
  if (mainnetConfig.has("tokens.dai")) {
    const daiContract = tryCreateTokenContract(
      "DAI",
      "dai",
      mainnetConfig,
      networkName,
      hre
    );
    if (daiContract) {
      tokens.dai = { contract: daiContract };

      const daiConfig = mainnetConfig.get("tokens.dai");
      console.log(daiConfig);
      if (daiConfig.has("adminAddress")) {
        tokens.dai.admin = daiConfig.get("adminAddress"); // to mint fresh DAIs on ethereum
      }
    }
  }

  // WETH
  if (mainnetConfig.has("tokens.wEth")) {
    const wEthContract = tryCreateTokenContract(
      "WETH",
      "wEth",
      mainnetConfig,
      networkName,
      hre
    );
    if (wEthContract) {
      tokens.wEth = { contract: wEthContract };
    }
  }

  // Compound tokens
  // CDAI
  if (mainnetConfig.has("tokens.cDai")) {
    const cDaiContract = tryCreateTokenContract(
      "CDAI",
      "cDai",
      mainnetConfig,
      networkName,
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
  if (mainnetConfig.has("tokens.cwEth")) {
    const cEthContract = tryCreateTokenContract(
      "CWETH",
      "cwEth",
      mainnetConfig,
      networkName,
      hre
    );
    if (cEthContract) {
      tokens.cwEth = {
        contract: cEthContract,
        isCompoundToken: true,
      };
    }
  }

  return tokens;
}

function tryCreateTokenContract(tokenName, configName, mainnetConfig, networkName, hre) {
  if (!mainnetConfig.has(`tokens.${configName}`)) {
    return null;
  }
  const tokenConfig = mainnetConfig.get(`tokens.${configName}`);

  if (!tokenConfig.has("address")) {
    console.warn(
      `Config for ${tokenName} does not specify an address on ${networkName}. Contract therefore not available.`
    );
    return null;
  }
  const tokenAddress = tokenConfig.get("address");
  if (!tokenConfig.has("abi")) {
    console.warn(
      `Config for ${tokenName} does not specify an abi file for on ${networkName}. Contract therefore not available.`
    );
    return null;
  }
  const tokenAbi = requireFromProjectRoot(tokenConfig.get("abi"));

  console.info(
    `$ token ${tokenName} ABI loaded. Address: ${tokenAddress}`
  );
  return new hre.ethers.Contract(tokenAddress, tokenAbi, hre.ethers.provider);
}

function tryGetCompoundEnv(mainnetConfig, networkName, hre) {
  if (!mainnetConfig.has("compound")) {
    return null;
  }
  let compoundConfig = mainnetConfig.get("compound");

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
    `${networkName} Compound ABI loaded. Unitroller address: ${unitrollerAddress}`
  );
  return compound;
}

function tryGetAaveEnv(mainnetConfig, networkName, hre) {
  
  if (!mainnetConfig.has("aave")) {
    return null;
  }
  const aaveConfig = mainnetConfig.get("aave");

  if (!(
    aaveConfig.has("addressesProviderAddress")
    && aaveConfig.has("addressesProviderAbi")
    && aaveConfig.has("lendingPoolAddress")
    && aaveConfig.has("lendingPoolAbi"))
  ) {
    console.warn(
      "Config for Aave does not specify an address provider. Aave is therefore not available."
    );
    return null;
  }

  const addressesProviderAddress = aaveConfig.get("addressesProviderAddress");
  const lendingPoolAddress = aaveConfig.get("lendingPoolAddress")
  const addressesProviderAbi = requireFromProjectRoot(aaveConfig.get("addressesProviderAbi"));
  const lendingPoolAbi = requireFromProjectRoot(aaveConfig.get("lendingPoolAbi"));

  const addressesProvider = new hre.ethers.Contract(
    addressesProviderAddress,
    addressesProviderAbi,
    hre.ethers.provider
  );

  const lendingPool = new hre.ethers.Contract(
    lendingPoolAddress,
    lendingPoolAbi,
    hre.ethers.provider
  );

  const aave = {
    lendingPool: lendingPool,
    addressesProvider: addressesProvider
  };

  console.info(
    `${networkName} Aave ABI loaded. LendingPool is at: ${lendingPoolAddress}`
  );
  return aave;
}

function tryGetMangroveEnv(mainnetConfig, networkName, hre) {
  if (!mainnetConfig.has("mangrove")) {
    console.warn(`Mangrove is not pre deployed on ${networkName} mainnet`);
    return null;
  }
  mangroveConfig = mainnetConfig.get("mangrove");
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
      "Config for Mangrove does not specify an abi file. Mangrove env is therefore not available."
    );
  }

  // TODO Can we read the active markets?

  console.info(`${networkName} Mangrove ABI loaded. Address: ${mangroveAddress}`);
  return mangrove;
}
