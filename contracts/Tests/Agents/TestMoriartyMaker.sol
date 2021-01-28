// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;
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

  function makerTrade(DC.SingleOrder calldata order, address taker)
    public
    override
    returns (bytes32 ret)
  {
    bool _succeed = succeed;
    if (order.offerId == dummy) {
      succeed = false;
    }
    if (_succeed) {
      bool s = IERC20(order.base).transfer(taker, order.wants);
      ret = s ? bytes32(0) : bytes32(uint(2));
    } else {
      assert(false);
    }
  }

  function makerPosthook(
    DC.SingleOrder calldata order,
    DC.OrderResult calldata result
  ) external override {}

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public {
    dex.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    dex.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    dex.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    dex.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    uint density = dex.config(base, quote).local.density;
    uint gasbase = dex.config(base, quote).local.gasbase;
    dummy = dex.newOffer({
      base: base,
      quote: quote,
      wants: 1,
      gives: density * (gasbase + 100000),
      gasreq: 100000,
      gasprice: 0,
      pivotId: 0
    }); //dummy offer
  }

  function provisionDex(uint amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success);
  }

  function approveDex(IERC20 token, uint amount) public {
    token.approve(address(dex), amount);
  }

  receive() external payable {}
}
