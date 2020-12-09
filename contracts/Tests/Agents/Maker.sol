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
    address tk_A,
    address tk_B,
    address payable dex
  ) {
    bool success = IERC20(tk_A).approve(dex, 2**256 - 1);
    require(success, "Failed to give allowance.");

    execGas = 1000;
    A_TOKEN = tk_A;
    B_TOKEN = tk_B;
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
      uint gasprice = Dex(DEX).config(A_TOKEN, B_TOKEN).gasprice; //current price per gas spent in offer fails
      uint available = Dex(DEX).balanceOf(address(this)) - (gasprice * execGas); //enabling delegatecall
      require(available >= 0, "Insufficient funds to push offer."); //better fail early
      Dex(DEX).newOffer(A_TOKEN, B_TOKEN, wants, gives, execGas, position); // discards offerId
    }
  }

  function pullOffer(uint offerId) external {
    if (msg.sender == admin) {
      uint releasedWei = Dex(DEX).cancelOffer(A_TOKEN, B_TOKEN, offerId); // Dex will release provision of offerId
      Dex(DEX).withdraw(releasedWei);
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

  function execute(
    address,
    address,
    uint,
    uint,
    uint,
    uint
  ) external view override {
    //making sure execution is sent by the corresponding dex
    require(msg.sender == DEX);
  }
}
