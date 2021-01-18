// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../../ERC20.sol";
import "../../Dex.sol";

// struct Trade {
//   address base;
//   address quote;
//   uint takerWants;
//   uint takerGives;
//   address taker;
//   uint offerGasprice;
//   uint offerGasreq;
//   uint offerId;
//   uint offerWants;
//   uint offerGives;
//   bool offerWillDelete;
// }
//
//
// event Execute(
//   address dex,
//   address base,
//   address quote,
//   uint offerId,
//   uint takerWants,
//   uint takerGives
// );

contract UniSwapMaker is IMaker {
  ERC20 tk0;
  ERC20 tk1;
  Dex dex;
  address private admin;
  uint gasreq = 100_000;
  uint fraction;

  constructor(
    ERC20 _tk0, // makerWants
    ERC20 _tk1, // makerGives
    Dex _dex,
    uint _fraction
  ) {
    admin = msg.sender;
    tk0 = _tk0;
    tk1 = _tk1;
    dex = _dex; // FMD or FTD
    fraction = _fraction;
  }

  receive() external payable {}

  function makerTrade(IMaker.Trade calldata trade)
    external
    override
    returns (bytes32)
  {
    require(msg.sender == address(dex), "Illegal call");
    emit Execute(
      msg.sender,
      trade.base, // takerGives
      trade.quote, // takerWants
      trade.offerId,
      trade.takerWants,
      trade.takerGives
    );
    try ERC20(trade.quote).transfer(trade.taker, trade.takerWants) {
      // try catch useless but clarifies
      return "OK";
    } catch {
      return "FailedTransfer";
    }
  }

  // struct Posthook {
  //   address base;
  //   address quote;
  //   uint takerWants;
  //   uint takerGives;
  //   uint offerId;
  //   bool offerDeleted;
  // }

  function makerPosthook(IMaker.Posthook calldata posthook) external override {
    // taker has paid maker
    uint newGives = ERC20(posthook.quote).balanceOf(address(this)) / fraction;
    uint x = (fraction * 997) / 1000;
    uint newWants =
      (ERC20(posthook.base).balanceOf(address(this)) * x) / (1 + x);
    dex.updateOffer(
      posthook.base,
      posthook.quote,
      newWants,
      newGives,
      gasreq,
      0,
      0,
      posthook.offerId
    );
  }
}
