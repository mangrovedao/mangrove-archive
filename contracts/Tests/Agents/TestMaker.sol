// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./Passthrough.sol";
import "../../interfaces.sol";
import "../../Dex.sol";

contract TestMaker is IMaker, Passthrough {
  Dex dex;
  address atk;
  address btk;
  bool shouldFail;

  constructor(
    Dex _dex,
    address _atk,
    address _btk,
    bool _failer
  ) {
    dex = _dex;
    atk = _atk;
    btk = _btk;
    shouldFail = _failer;
  }

  event Execute(uint takerWants, uint takerGives, uint gasprice, uint offerId);

  receive() external payable {}

  function execute(
    address ofrToken,
    address reqToken,
    uint takerWants,
    uint takerGives,
    uint gasprice,
    uint offerId
  ) public override {
    atk = ofrToken;
    btk = reqToken;
    emit Execute(takerWants, takerGives, gasprice, offerId);
    assert(!shouldFail);
  }

  function cancelOffer(Dex _dex, uint offerId) public returns (uint) {
    return (_dex.cancelOffer(atk, btk, offerId));
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    return (dex.newOffer(atk, btk, wants, gives, gasreq, pivotId));
  }

  function cancelOffer(uint offerId) public {
    dex.cancelOffer(atk, btk, offerId);
  }

  function provisionDex(uint amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success, "provision dex failed");
  }

  function withdrawDex(uint amount) public returns (bool) {
    return dex.withdraw(amount);
  }

  function approve(IERC20 token, uint amount) public {
    token.approve(address(dex), amount);
  }

  function freeWei() public view returns (uint) {
    return dex.balanceOf(address(this));
  }
}
