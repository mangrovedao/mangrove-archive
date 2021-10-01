// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../AbstractMangrove.sol";
import "../MgvLib.sol";
import "hardhat/console.sol";
import "@giry/hardhat-test-solidity/test.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";
import {MgvReader} from "../periphery/MgvReader.sol";

// In these tests, the testing contract is the market maker.
contract Reader_Test is HasMgvEvents {
  receive() external payable {}

  AbstractMangrove mgv;
  TestMaker mkr;
  MgvReader reader;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT);
    mkr = MakerSetup.setup(mgv, base, quote);
    reader = new MgvReader(address(mgv));

    address(mkr).transfer(10 ether);

    bool noRevert;
    (noRevert, ) = address(mgv).call{value: 10 ether}("");

    mkr.provisionMgv(5 ether);

    baseT.mint(address(this), 2 ether);
    quoteT.mint(address(mkr), 1 ether);

    baseT.approve(address(mgv), 1 ether);
    quoteT.approve(address(mgv), 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(mkr), "maker[$A,$B]");
  }

  function read_packed_test() public {
    (
      uint currentId,
      uint[] memory offerIds,
      ML.Offer[] memory offers,
      ML.OfferDetail[] memory details
    ) = reader.book(base, quote, 0, 50);

    TestEvents.eq(offerIds.length, 0, "ids: wrong length on 2elem");
    TestEvents.eq(offers.length, 0, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 0, "details: wrong length on 1elem");
    // test 1 elem
    mkr.newOffer(1 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.book(base, quote, 0, 50);

    TestEvents.eq(offerIds.length, 1, "ids: wrong length on 1elem");
    TestEvents.eq(offers.length, 1, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 1, "details: wrong length on 1elem");

    // test 2 elem
    mkr.newOffer(0.9 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.book(base, quote, 0, 50);

    TestEvents.eq(offerIds.length, 2, "ids: wrong length on 2elem");
    TestEvents.eq(offers.length, 2, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 2, "details: wrong length on 1elem");

    // test 2 elem read from elem 1
    (currentId, offerIds, offers, details) = reader.book(base, quote, 1, 50);
    TestEvents.eq(
      offerIds.length,
      1,
      "ids: wrong length 2elem start from id 1"
    );
    TestEvents.eq(offers.length, 1, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 1, "details: wrong length on 1elem");

    // test 3 elem read in chunks of 2
    mkr.newOffer(0.8 ether, 1 ether, 10_000, 0);
    (currentId, offerIds, offers, details) = reader.book(base, quote, 0, 2);
    TestEvents.eq(
      offerIds.length,
      2,
      "ids: wrong length on 3elem chunk size 2"
    );
    TestEvents.eq(offers.length, 2, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 2, "details: wrong length on 1elem");

    // test offer order
    (currentId, offerIds, offers, details) = reader.book(base, quote, 0, 50);
    TestEvents.eq(offers[0].wants, 0.8 ether, "wrong wants for offers[0]");
    TestEvents.eq(offers[1].wants, 0.9 ether, "wrong wants for offers[0]");
    TestEvents.eq(offers[2].wants, 1 ether, "wrong wants for offers[0]");
  }
}
