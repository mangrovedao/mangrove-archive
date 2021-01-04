// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./Passthrough.sol";
import "../../interfaces.sol";
import "../../Dex.sol";

contract TestMaker is IMaker, Passthrough {
  Dex dex;
  address base;
  address quote;
  bool shouldFail;
  bool _shouldRevert;

  constructor(
    Dex _dex,
    address _base,
    address _quote,
    bool _failer
  ) {
    dex = _dex;
    base = _base;
    quote = _quote;
    shouldFail = _failer;
  }

  event Execute(uint takerWants, uint takerGives, uint gasprice, uint offerId);

  receive() external payable {}

  function shouldRevert(bool should) external {
    _shouldRevert = should;
  }

  function execute(
    address _base,
    address _quote,
    uint takerWants,
    uint takerGives,
    address taker,
    uint gaspriceEstimate,
    uint offerId
  ) public virtual override returns (bytes32) {
    _base; // silence warning
    _quote; // silence warning
    taker; // silence warning
    emit Execute(takerWants, takerGives, gaspriceEstimate, offerId);
    if (_shouldRevert) {
      bytes32[1] memory three = [bytes32("testMaker/revert")];
      assembly {
        revert(three, 32)
      }
    }
    if (!shouldFail) {
      try IERC20(base).transfer(taker, takerWants) {
        return "testMaker/ok";
      } catch {
        return "testMaker/transferFail";
      }
    } else {
      return "testMaker/fail";
    }
  }

  function cancelOffer(Dex _dex, uint offerId) public {
    _dex.cancelOffer(base, quote, offerId, false);
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    return (dex.newOffer(base, quote, wants, gives, gasreq, pivotId));
  }

  function cancelOffer(uint offerId) public {
    dex.cancelOffer(base, quote, offerId, false);
  }

  function provisionDex(uint amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success, "provision dex failed");
  }

  function withdrawDex(uint amount) public returns (bool) {
    return dex.withdraw(amount);
  }

  function freeWei() public view returns (uint) {
    return dex.balanceOf(address(this));
  }
}
