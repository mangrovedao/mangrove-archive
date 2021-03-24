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
import "./Agents/TestTaker.sol";
import "./Agents/MM1.sol";

contract MM1T_Test {
  receive() external payable {}

  Dex dex;
  TestTaker tkr;
  TestMaker mkr;
  MM1 mm1;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);
    tkr = TakerSetup.setup(dex, base, quote);
    mkr = MakerSetup.setup(dex, base, quote);
    mm1 = new MM1{value: 2 ether}(dex, base, quote);

    address(tkr).transfer(10 ether);
    address(mkr).transfer(10 ether);

    //bool noRevert;
    //(noRevert, ) = address(dex).call{value: 10 ether}("");

    mkr.provisionDex(5 ether);

    baseT.mint(address(tkr), 10 ether);
    baseT.mint(address(mkr), 10 ether);
    baseT.mint(address(mm1), 2 ether);

    quoteT.mint(address(tkr), 10 ether);
    quoteT.mint(address(mkr), 10 ether);
    quoteT.mint(address(mm1), 2 ether);

    mm1.refresh();

    //baseT.approve(address(dex), 1 ether);
    //quoteT.approve(address(dex), 1 ether);
    tkr.approveDex(quoteT, 1000 ether);
    tkr.approveDex(baseT, 1000 ether);
    mkr.approveDex(quoteT, 1000 ether);
    mkr.approveDex(baseT, 1000 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");
    Display.register(address(tkr), "taker[$A,$B]");
    //Display.register(address(dual_mkr), "maker[$B,$A]");
    Display.register(address(mkr), "maker");
    Display.register(address(mm1), "MM1");
  }

  function ta_test() public {
    Display.logOfferBook(dex, base, quote, 3);
    Display.logOfferBook(dex, quote, base, 3);
    (DexCommon.Offer memory ofr, DexCommon.OfferDetail memory det) =
      dex.offerInfo(base, quote, 1);
    console.log("prev", ofr.prev);
    mkr.newOffer(base, quote, 0.05 ether, 0.1 ether, 200_000, 0);
    mkr.newOffer(quote, base, 0.05 ether, 0.05 ether, 200_000, 0);
    Display.logOfferBook(dex, base, quote, 3);
    Display.logOfferBook(dex, quote, base, 3);

    tkr.marketOrder(0.01 ether, 0.01 ether);
    Display.logOfferBook(dex, base, quote, 3);
    Display.logOfferBook(dex, quote, base, 3);

    mkr.newOffer(base, quote, 0.05 ether, 0.1 ether, 200_000, 0);
    mm1.refresh();
    Display.logOfferBook(dex, base, quote, 3);
    Display.logOfferBook(dex, quote, base, 3);
  }
}
