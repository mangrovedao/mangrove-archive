// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./Passthrough.sol";
import "../../interfaces.sol";
import "../../Dex.sol";
import "../../DexPack.sol";
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

  receive() external payable {}

  event Execute(
    address dex,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );

  function logExecute(
    address dex,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  ) external {
    emit Execute(dex, base, quote, offerId, takerWants, takerGives);
  }

  function shouldRevert(bool should) external {
    _shouldRevert = should;
  }

  function shouldFail(bool should) external {
    _shouldFail = should;
  }

  function approveDex(IERC20 token, uint amount) external {
    token.approve(address(_dex), amount);
  }

  function transferToken(
    IERC20 token,
    address to,
    uint amount
  ) external {
    token.transfer(to, amount);
  }

  function makerTrade(DC.SingleOrder calldata order)
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
      IERC20(order.base).approve(address(_dex), 0);
      bytes32[1] memory refuse_msg = [bytes32("testMaker/transferFail")];
      assembly {
        return(refuse_msg, 32)
      }
      //revert("testMaker/fail");
    }
  }

  function makerPosthook(
    DC.SingleOrder calldata order,
    DC.OrderResult calldata result
  ) external virtual override {}

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    return (_dex.newOffer(_base, _quote, wants, gives, gasreq, 0, pivotId));
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) public returns (uint) {
    return (
      _dex.newOffer(_base, _quote, wants, gives, gasreq, gasprice, pivotId)
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
      _dex.updateOffer(_base, _quote, wants, gives, gasreq, 0, pivotId, offerId)
    );
  }

  function retractOffer(uint offerId) public {
    _dex.retractOffer(_base, _quote, offerId, false);
  }

  function deleteOffer(uint offerId) public {
    _dex.retractOffer(_base, _quote, offerId, true);
  }

  function provisionDex(uint amount) public {
    _dex.fund{value: amount}(address(this));
  }

  function withdrawDex(uint amount) public returns (bool) {
    return _dex.withdraw(amount);
  }

  function freeWei() public view returns (uint) {
    return _dex.balanceOf(address(this));
  }
}
