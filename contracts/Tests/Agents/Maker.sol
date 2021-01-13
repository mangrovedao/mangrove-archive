// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../../interfaces.sol";
import "../../Dex.sol";

contract Maker is IMaker {
  address immutable A_TOKEN;
  address immutable B_TOKEN;
  address payable immutable DEX; // Address of a (A,B) DEX
  address private admin;
  uint private execGas;

  constructor(
    address base,
    address quote,
    address payable dex
  ) {
    bool success = IERC20(base).approve(dex, 2**256 - 1);
    require(success, "Failed to give allowance.");

    execGas = 1000;
    A_TOKEN = base;
    B_TOKEN = quote;
    DEX = dex;
    admin = msg.sender;
  }

  function setExecGas(uint cost) external {
    if (msg.sender == admin) {
      execGas = cost;
    }
  }

  function setAdmin(address newAdmin) external {
    if (msg.sender == admin) {
      admin = newAdmin;
    }
  }

  function pushOffer(
    uint wants,
    uint gives,
    uint position
  ) external payable {
    if (msg.sender == admin) {
      payable(DEX).transfer(msg.value);
      uint gasprice = Dex(DEX).config(A_TOKEN, B_TOKEN).global.gasprice; //current price per gas spent in offer fails
      uint available = Dex(DEX).balanceOf(address(this)) - (gasprice * execGas); //enabling delegatecall
      require(available >= 0, "Insufficient funds to push offer."); //better fail early
      Dex(DEX).newOffer(A_TOKEN, B_TOKEN, wants, gives, execGas, 0, position); // discards offerId
    }
  }

  function pullOffer(uint offerId) external {
    if (msg.sender == admin) {
      Dex(DEX).cancelOffer(A_TOKEN, B_TOKEN, offerId, false); // Dex will release provision of offerId
      Dex(DEX).withdraw(Dex(DEX).balanceOf(address(this)));
    }
  }

  //need to be able to receive WEIs for collecting freed provisions
  receive() external payable {}

  function transferWei(uint amount, address payable receiver) external {
    if (msg.sender == admin) {
      receiver.transfer(amount);
    }
  }

  function transferToken(
    address token,
    address to,
    uint value
  ) external returns (bool) {
    if (msg.sender == admin) {
      return IERC20(token).transferFrom(address(this), to, value);
    } else {
      return false;
    }
  }

  function makerTrade(IMaker.Trade calldata trade)
    external
    view
    override
    returns (bytes32)
  {
    trade; // silence compiler warning
    //making sure execution is sent by the corresponding dex
    require(msg.sender == DEX);
    return bytes32(0);
  }

  function makerPosthook(IMaker.Posthook calldata posthook) external override {}
}
