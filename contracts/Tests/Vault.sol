// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Dex.sol";
import "../interfaces.sol";
import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";

// In these tests, the testing contract is the market maker.
contract Vault_Test {
  receive() external payable {}

  Dex dex;
  TestMaker mkr;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);
    mkr = MakerSetup.setup(dex, base, quote);

    address(mkr).transfer(10 ether);

    mkr.provisionDex(5 ether);
    bool noRevert;
    (noRevert, ) = address(dex).call{value: 10 ether}("");

    baseT.mint(address(mkr), 2 ether);
    quoteT.mint(address(this), 2 ether);

    baseT.approve(address(dex), 1 ether);
    quoteT.approve(address(dex), 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Test Contract");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker[$A,$B]");
  }

  function initial_vault_value_test() public {
    TestEvents.eq(
      dex.vault(),
      address(this),
      "initial vault value should be dex creator"
    );
  }

  function gov_can_set_vault_test() public {
    dex.setVault(address(0));
    TestEvents.eq(dex.vault(), address(0), "gov should be able to set vault");
  }
}
