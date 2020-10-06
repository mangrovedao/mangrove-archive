// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./interfaces.sol";
import "./Dex.sol";

contract Maker is IMaker {
  address immutable A_TOKEN;
  address immutable B_TOKEN;
  address payable immutable DEXAB; // Address of a (A,B) DEX
  address payable immutable DEXBA; // Address of a (B,A) DEX
  address private admin;
  uint256 private execGas;

  constructor(
    address tk_A,
    address tk_B,
    address payable dexAB,
    address payable dexBA
  ) {
    require(
      (address(Dex(dexAB).REQ_TOKEN()) == tk_A) &&
        (address(Dex(dexAB).OFR_TOKEN()) == tk_B)
    );
    require(
      (address(Dex(dexBA).REQ_TOKEN()) == tk_B) &&
        (address(Dex(dexBA).OFR_TOKEN()) == tk_A)
    );
    bool successAB = IERC20(tk_A).approve(dexAB, 2**256 - 1);
    bool successBA = IERC20(tk_B).approve(dexBA, 2**256 - 1);
    require(successAB && successBA, "Failed to give allowance.");

    execGas = 1000;
    A_TOKEN = tk_A;
    B_TOKEN = tk_B;
    DEXAB = dexAB;
    DEXBA = dexBA;
    admin = msg.sender;
  }

  function validate(uint256 orderId, address dex) internal {
    // Throws if orderId@dex is not in the whitelist
    require(dex == DEXAB || dex == DEXBA);
  }

  function setExecGas(uint256 cost) external {
    if (msg.sender == admin) {
      execGas = cost;
    }
  }

  function setAdmin(address newAdmin) external {
    if (msg.sender == admin) {
      admin = newAdmin;
    }
  }

  function selectDex(address tk1, address tk2)
    internal
    view
    returns (address payable)
  {
    if ((tk1 == A_TOKEN) && (tk2 == B_TOKEN)) {
      return DEXAB;
    }
    if ((tk1 == B_TOKEN) && (tk2 == A_TOKEN)) {
      return DEXBA;
    }
    require(false);
  }

  function pushOrder(
    address tk1,
    address tk2,
    uint256 wants,
    uint256 gives,
    uint256 position
  ) external payable {
    if (msg.sender == admin) {
      address payable dex = selectDex(tk1, tk2);
      dex.transfer(msg.value);
      uint256 penaltyPerGas = Dex(dex).penaltyPerGas(); //current price per gas spent in offer fails
      uint256 available = Dex(dex).balanceOf(address(this)) -
        (penaltyPerGas * execGas); //enabling delegatecall
      require(available >= 0, "Insufficient funds to push order."); //better fail early
      uint256 orderId = Dex(dex).newOrder(wants, gives, execGas, position);
    }
  }

  function pullOrder(
    address tk1,
    address tk2,
    uint256 orderId
  ) external {
    if (msg.sender == admin) {
      address payable dex = selectDex(tk1, tk2);
      uint256 releasedWei = Dex(dex).cancelOrder(orderId); // Dex will release provision of orderId
      Dex(dex).withdraw(releasedWei);
    }
  }

  //need to be able to receive WEIs for collecting freed provisions
  receive() external payable {}

  function transferWei(uint256 amount, address payable receiver) external {
    if (msg.sender == admin) {
      receiver.transfer(amount);
    }
  }

  function transferToken(
    address token,
    address to,
    uint256 value
  ) external returns (bool) {
    if (msg.sender == admin) {
      return IERC20(token).transferFrom(address(this), to, value);
    } else {
      return false;
    }
  }

  function execute(
    uint256 orderId,
    uint256,
    uint256,
    uint256
  ) external override {
    //making sure execution is sent by the corresponding dex
    validate(orderId, msg.sender);
  }
}
