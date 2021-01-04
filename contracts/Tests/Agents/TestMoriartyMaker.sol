// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "./Passthrough.sol";
import "../../interfaces.sol";
import "../../Dex.sol";

contract TestMoriartyMaker is IMaker, Passthrough {
  Dex dex;
  address base;
  address quote;
  bool succeed;
  uint dummy;

  constructor(
    Dex _dex,
    address _base,
    address _quote
  ) {
    dex = _dex;
    base = _base;
    quote = _quote;
    succeed = true;
  }

  function execute(
    address,
    address,
    uint takerWants,
    uint,
    address taker,
    uint,
    uint offerId
  ) public override returns (bytes32 ret) {
    bool _succeed = succeed;
    if (offerId == dummy) {
      succeed = false;
    }
    if (_succeed) {
      bool s = IERC20(base).transfer(taker, takerWants);
      ret = s ? bytes32(0) : bytes32(uint(2));
    } else {
      assert(false);
    }
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public {
    dex.newOffer(base, quote, wants, gives, gasreq, pivotId);
    dex.newOffer(base, quote, wants, gives, gasreq, pivotId);
    dex.newOffer(base, quote, wants, gives, gasreq, pivotId);
    dex.newOffer(base, quote, wants, gives, gasreq, pivotId);
    uint density = dex.config(base, quote).density;
    uint gasbase = dex.config(base, quote).gasbase;
    dummy = dex.newOffer({
      base: base,
      quote: quote,
      wants: 1,
      gives: density * (gasbase + 100000),
      gasreq: 100000,
      pivotId: 0
    }); //dummy offer
  }

  function provisionDex(uint amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success);
  }

  function approve(IERC20 token, uint amount) public {
    token.approve(address(dex), amount);
  }

  receive() external payable {}
}
