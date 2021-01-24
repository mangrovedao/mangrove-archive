// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../Dex.sol";
import "../DexCommon.sol";
import "../interfaces.sol";
import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/TestMoriartyMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

// In these tests, the testing contract is the market maker.
contract Gas_Test {
  receive() external payable {}

  Dex _dex;
  TestTaker _tkr;
  address _base;
  address _quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    _base = address(baseT);
    _quote = address(quoteT);
    _dex = DexSetup.setup(baseT, quoteT);

    bool noRevert;
    (noRevert, ) = address(_dex).call{value: 10 ether}("");

    baseT.mint(address(this), 2 ether);
    baseT.approve(address(_dex), 1 ether);
    quoteT.approve(address(_dex), 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(_base, "$A");
    Display.register(_quote, "$B");
    Display.register(address(_dex), "dex");

    _dex.newOffer(_base, _quote, 1 ether, 1 ether, 100_000, 0, 0);
    console.log("dex", address(_dex));

    _tkr = TakerSetup.setup(_dex, _base, _quote);
    quoteT.mint(address(_tkr), 2 ether);
    _tkr.approveDex(quoteT, 2 ether);
    Display.register(address(_tkr), "Taker");
  }

  function getStored()
    internal
    returns (
      Dex,
      TestTaker,
      address,
      address
    )
  {
    return (_dex, _tkr, _base, _quote);
  }

  function update_min_offer_test() public {
    (Dex dex, , address base, address quote) = getStored();
    uint g = gasleft();
    uint h;
    dex.updateOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 1, 1);
    h = gasleft();
    console.log("Gas used", g - h);
  }

  function update_full_offer_test() public {
    (Dex dex, , address base, address quote) = getStored();
    uint g = gasleft();
    uint h;
    dex.updateOffer(base, quote, 0.5 ether, 1 ether, 100_001, 0, 1, 1);
    h = gasleft();
    console.log("Gas used", g - h);
  }

  function new_offer_test() public {
    (Dex dex, , address base, address quote) = getStored();
    uint g = gasleft();
    uint h;
    dex.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 1);
    h = gasleft();
    console.log("Gas used", g - h);
  }

  function take_offer_test() public {
    (Dex dex, TestTaker tkr, address base, address quote) = getStored();
    uint g = gasleft();
    uint h;
    tkr.snipe(dex, base, quote, 1, 1 ether, 1 ether, 100_000);
    h = gasleft();
    console.log("Gas used", g - h);
  }

  function partial_take_offer_test() public {
    (Dex dex, TestTaker tkr, address base, address quote) = getStored();
    uint g = gasleft();
    uint h;
    tkr.snipe(dex, base, quote, 1, 0.5 ether, 0.5 ether, 100_000);
    h = gasleft();
    console.log("Gas used", g - h);
  }

  function market_order_1_test() public {
    (Dex dex, TestTaker tkr, address base, address quote) = getStored();
    uint g = gasleft();
    uint h;
    tkr.simpleMarketOrder(dex, base, quote, 1 ether, 1 ether);
    h = gasleft();
    console.log("Gas used", g - h);
  }

  function market_order_8_test() public {
    (Dex dex, TestTaker tkr, address base, address quote) = getStored();
    _dex.newOffer(_base, _quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    _dex.newOffer(_base, _quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    _dex.newOffer(_base, _quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    _dex.newOffer(_base, _quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    _dex.newOffer(_base, _quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    _dex.newOffer(_base, _quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    _dex.newOffer(_base, _quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    uint g = gasleft();
    uint h;
    tkr.simpleMarketOrder(dex, base, quote, 1 ether, 1 ether);
    h = gasleft();
    console.log("Gas used", g - h);
  }
}
