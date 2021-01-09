// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./Passthrough.sol";
import "../../interfaces.sol";
import "../../Dex.sol";
import "hardhat/console.sol";

contract TestMaker is IMaker, Passthrough {
  Dex _dex;
  address _base;
  address _quote;
  bool _shouldFail;
  bool _shouldRevert;

  constructor(
    Dex dex,
    IERC20 base,
    IERC20 quote
  ) {
    _dex = dex;
    _base = address(base);
    _quote = address(quote);
  }

  event Execute(uint takerWants, uint takerGives, uint gasprice, uint offerId);

  receive() external payable {}

  function shouldRevert(bool should) external {
    _shouldRevert = should;
  }

  function shouldFail(bool should) external {
    _shouldFail = should;
  }

  function makerTrade(IMaker.Trade calldata trade)
    public
    virtual
    override
    returns (bytes32)
  {
    emit Execute(
      trade.takerWants,
      trade.takerGives,
      trade.offerGasprice,
      trade.offerId
    );
    if (_shouldRevert) {
      bytes32[1] memory three = [bytes32("testMaker/revert")];
      assembly {
        revert(three, 32)
      }
    }
    if (!_shouldFail) {
      try IERC20(trade.base).transfer(trade.taker, trade.takerWants) {
        return "testMaker/ok";
      } catch {
        return "testMaker/transferFail";
      }
    } else {
      return "testMaker/fail";
    }
  }

  function makerHandoff(IMaker.Handoff calldata handoff)
    external
    virtual
    override
  {}

  function cancelOffer(Dex dex, uint offerId) public {
    dex.cancelOffer(_base, _quote, offerId, false);
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    return (_dex.newOffer(_base, _quote, wants, gives, gasreq, pivotId));
  }

  function cancelOffer(uint offerId) public {
    _dex.cancelOffer(_base, _quote, offerId, false);
  }

  function provisionDex(uint amount) public {
    _dex.fund{value: amount}();
  }

  function withdrawDex(uint amount) public returns (bool) {
    return _dex.withdraw(amount);
  }

  function freeWei() public view returns (uint) {
    return _dex.balanceOf(address(this));
  }
}
