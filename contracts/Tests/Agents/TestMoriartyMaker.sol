// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;
import "./Passthrough.sol";
import "../../interfaces.sol";
import "../../Mangrove.sol";
import {IMaker} from "../../MgvCommon.sol";

contract TestMoriartyMaker is IMaker, Passthrough {
  Mangrove mgv;
  address base;
  address quote;
  bool succeed;
  uint dummy;

  constructor(
    Mangrove _mgv,
    address _base,
    address _quote
  ) {
    mgv = _mgv;
    base = _base;
    quote = _quote;
    succeed = true;
  }

  function makerTrade(MC.SingleOrder calldata order)
    public
    override
    returns (bytes32 ret)
  {
    bool _succeed = succeed;
    if (order.offerId == dummy) {
      succeed = false;
    }
    if (_succeed) {
      ret = bytes32(0);
    } else {
      assert(false);
    }
  }

  function makerPosthook(
    MC.SingleOrder calldata order,
    MC.OrderResult calldata result
  ) external override {}

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public {
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    uint density = mgv.getConfig(base, quote).local.density;
    uint offer_gasbase = mgv.getConfig(base, quote).local.offer_gasbase;
    dummy = mgv.newOffer({
      base: base,
      quote: quote,
      wants: 1,
      gives: density * (offer_gasbase + 100000),
      gasreq: 100000,
      gasprice: 0,
      pivotId: 0
    }); //dummy offer
  }

  function provisionMgv(uint amount) public {
    (bool success, ) = address(mgv).call{value: amount}("");
    require(success);
  }

  function approveMgv(IERC20 token, uint amount) public {
    token.approve(address(mgv), amount);
  }

  receive() external payable {}
}
