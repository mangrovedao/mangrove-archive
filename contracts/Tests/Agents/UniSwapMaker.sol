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

// Dex must be provisioned in the name of UniSwapMaker
// UniSwapMaker must have ERC20 credit in tk0 and tk1 and these credits should not be shared (since contract is memoryless)
contract UniSwapMaker is IMaker {
  Dex dex;
  address private admin;
  uint gasreq = 100_000;
  uint fraction;
  uint fee;

  mapping(uint => uint) percentile;

  constructor(
    Dex _dex,
    uint _fraction,
    uint _fee
  ) {
    admin = msg.sender;
    dex = _dex; // FMD or FTD
    fraction = _fraction;
    fee = _fee;
  }

  receive() external payable {}

  function setParams(uint _fee, uint _fraction) external {
    if (msg.sender == admin) {
      fee = _fee;
      fraction = _fraction;
    }
  }

  function withdraw(address recipient, uint amount) external {
    if (msg.sender == admin) {
      bool noRevert;
      (noRevert, ) = address(recipient).call{value: amount}("");
      require(noRevert);
    }
  }

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

  function newPrice(ERC20 tk, ERC20 _tk) internal view returns (uint, uint) {
    uint newGives = _tk.balanceOf(address(this)) / fraction;
    uint x = (fraction * fee) / 1000;
    uint newWants = (tk.balanceOf(address(this)) * x) / (1 + x);
    return (newWants, newGives);
  }

  function newOffer(
    address base,
    address quote,
    uint pivotId_bq,
    uint pivotId_qb
  ) public {
    (uint bq_wants, uint bq_gives) = newPrice(ERC20(base), ERC20(quote));
    (uint qb_wants, uint qb_gives) = newPrice(ERC20(quote), ERC20(base));
    uint newOfrId_bq =
      dex.newOffer(base, quote, bq_wants, bq_gives, gasreq, 0, pivotId_bq);
    uint newOfrId_qb =
      dex.newOffer(quote, base, qb_wants, qb_gives, gasreq, 0, pivotId_qb);
    newOfrId_bq; // should be recorded as step i of price curve discretization
    newOfrId_qb; // should be recorded as step i of price curve discretization
  }

  function makerPosthook(IMaker.Posthook calldata posthook) external override {
    // taker has paid maker
    (uint newWants, uint newGives) =
      newPrice(ERC20(posthook.quote), ERC20(posthook.base));
    uint pivotId;
    if (!posthook.offerDeleted) {
      pivotId = posthook.offerId;
    } else {
      // if offerId = n, try to reenter at position offer[n+1]
      pivotId = 0;
    }
    dex.updateOffer(
      posthook.base,
      posthook.quote,
      newWants,
      newGives,
      gasreq,
      0,
      pivotId,
      posthook.offerId
    );
    // for all pairs in opposite Dex:
    pivotId = 0; // if offerId = n, try to reenter at position offer[n+1]
    (newWants, newGives) = newPrice(
      ERC20(posthook.base),
      ERC20(posthook.quote)
    );
    dex.updateOffer(
      posthook.quote,
      posthook.base,
      newWants,
      newGives,
      gasreq,
      0,
      pivotId,
      posthook.offerId
    );
  }
}
