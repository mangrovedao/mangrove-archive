// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./Passthrough.sol";
import "../../interfaces.sol";
import "../../AbstractMangrove.sol";
import "../../MgvPack.sol";
import "hardhat/console.sol";
import {IMaker} from "../../MgvLib.sol";

contract TestMaker is IMaker, Passthrough {
  AbstractMangrove _mgv;
  address _base;
  address _quote;
  bool _shouldFail;
  bool _shouldRevert;

  constructor(
    AbstractMangrove mgv,
    IERC20 base,
    IERC20 quote
  ) {
    _mgv = mgv;
    _base = address(base);
    _quote = address(quote);
  }

  receive() external payable {}

  event Execute(
    address mgv,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );

  function logExecute(
    address mgv,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  ) external {
    emit Execute(mgv, base, quote, offerId, takerWants, takerGives);
  }

  function shouldRevert(bool should) external {
    _shouldRevert = should;
  }

  function shouldFail(bool should) external {
    _shouldFail = should;
  }

  function approveMgv(IERC20 token, uint amount) public {
    token.approve(address(_mgv), amount);
  }

  function transferToken(
    IERC20 token,
    address to,
    uint amount
  ) external {
    token.transfer(to, amount);
  }

  function makerTrade(ML.SingleOrder calldata order)
    public
    virtual
    override
    returns (bytes32 avoid_compilation_warning)
  {
    avoid_compilation_warning;
    if (_shouldRevert) {
      bytes32[1] memory revert_msg = [bytes32("testMaker/revert")];
      assembly {
        revert(revert_msg, 32)
      }
    }
    emit Execute(
      msg.sender,
      order.base,
      order.quote,
      order.offerId,
      order.wants,
      order.gives
    );
    if (_shouldFail) {
      IERC20(order.base).approve(address(_mgv), 0);
      bytes32[1] memory refuse_msg = [bytes32("testMaker/transferFail")];
      assembly {
        return(refuse_msg, 32)
      }
      //revert("testMaker/fail");
    }
  }

  function makerPosthook(
    ML.SingleOrder calldata order,
    ML.OrderResult calldata result
  ) external virtual override {}

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    return (_mgv.newOffer(_base, _quote, wants, gives, gasreq, 0, pivotId));
  }

  function newOffer(
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    return (_mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId));
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) public returns (uint) {
    return (
      _mgv.newOffer(_base, _quote, wants, gives, gasreq, gasprice, pivotId)
    );
  }

  function updateOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId,
    uint offerId
  ) public returns (uint) {
    return (
      _mgv.updateOffer(_base, _quote, wants, gives, gasreq, 0, pivotId, offerId)
    );
  }

  function retractOffer(uint offerId) public {
    _mgv.retractOffer(_base, _quote, offerId, false);
  }

  function retractOfferWithDeprovision(uint offerId) public {
    _mgv.retractOffer(_base, _quote, offerId, true);
  }

  function provisionMgv(uint amount) public {
    _mgv.fund{value: amount}(address(this));
  }

  function withdrawMgv(uint amount) public returns (bool) {
    return _mgv.withdraw(amount);
  }

  function freeWei() public view returns (uint) {
    return _mgv.balanceOf(address(this));
  }
}
