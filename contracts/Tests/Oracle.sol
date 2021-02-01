// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Dex.sol";
import "../DexCommon.sol";
import "../interfaces.sol";
import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";

contract DexOracle is IDexOracle {
  uint gasprice;
  uint density;

  function setGasprice(uint _gasprice) external {
    gasprice = _gasprice;
  }

  function setDensity(uint _density) external {
    density = _density;
  }

  function read(address base, address quote)
    external
    override
    returns (uint, uint)
  {
    return (gasprice, density);
  }
}

// In these tests, the testing contract is the market maker.
contract Oracle_Test {
  receive() external payable {}

  Dex dex;
  TestTaker tkr;
  DexOracle oracle;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    oracle = new DexOracle();
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);
  }

  function initial_oracle_is_zero_test() public {
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(
      config.global.oracle,
      address(0),
      "initial oracle should be 0"
    );
  }

  function set_oracle_test() public {
    dex.setOracle(address(oracle));
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(
      config.global.oracle,
      address(oracle),
      "oracle should be set"
    );
  }

  function set_oracle_density_test() public {
    dex.setOracle(address(oracle));
    oracle.setDensity(899);
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(config.local.density, 899, "density should be set");
  }

  function set_oracle_gasprice_test() public {
    dex.setOracle(address(oracle));
    oracle.setGasprice(901);
    DC.Config memory config = dex.config(base, quote);
    TestEvents.eq(config.global.gasprice, 901, "gasprice should be set");
  }
}
