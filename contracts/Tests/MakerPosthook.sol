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

contract MakerPosthook_Test is IMaker {
  Dex dex;
  TestTaker tkr;
  TestToken baseT;
  TestToken quoteT;
  address base;
  address quote;
  uint gasreq = 50_000;
  uint gasprice = 50; // will cover for a gasprice of 50 gwei/gas uint

  receive() external payable {}

  // address base;
  // address quote;
  // uint offerId;
  // bytes32 offer;
  // /* will evolve over time, initially the wants/gives from the taker's pov,
  //    then actual wants/give depending on how much the offer is ready */
  // uint wants;
  // uint gives;
  // /* only populated when necessary */
  // bytes32 offerDetail;

  function makerTrade(
    DexCommon.SingleOrder calldata trade,
    address taker,
    bool willDelete
  ) external override returns (bytes32 ret) {
    require(msg.sender == address(dex));
    emit Execute(
      msg.sender,
      trade.base,
      trade.quote,
      trade.offerId,
      trade.wants,
      trade.gives
    );
    TestToken(trade.base).transfer(taker, trade.wants);
    return "OK";
  }

  function makerPosthook(
    DexCommon.SingleOrder calldata order,
    DexCommon.OrderResult calldata result
  ) external override {
    require(msg.sender == address(dex));
    dex.updateOffer(
      order.base,
      order.quote,
      1 ether,
      1 ether,
      gasreq,
      gasprice,
      order.offerId,
      order.offerId
    );
  }

  function a_beforeAll() public {
    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);

    dex = DexSetup.setup(baseT, quoteT);
    tkr = TakerSetup.setup(dex, base, quote);

    address(tkr).transfer(10 ether);
    quoteT.mint(address(tkr), 1 ether);
    tkr.approveDex(baseT, 1 ether); // takerFee
    tkr.approveDex(quoteT, 1 ether);

    dex.fund{value: 10 ether}(address(this)); // for new offer and further updates

    dex.newOffer(base, quote, 1 ether, 1 ether, 50_000, 0, 0);
  }

  function update_offer_test() public {}
}
