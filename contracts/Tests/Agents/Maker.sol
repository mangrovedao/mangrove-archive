// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "../../interfaces.sol";
import "../../Dex.sol";

contract Maker is IMaker {
  address immutable A_TOKEN;
  address immutable B_TOKEN;
  address payable immutable DEXAB; // Address of a (A,B) DEX
  address payable immutable DEXBA; // Address of a (B,A) DEX
  address private admin;
  uint private execGas;

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
    return address(0x0); // silence unnamed return variable warning
  }

  function pushOffer(
    address tk1,
    address tk2,
    uint wants,
    uint gives,
    uint position
  ) external payable {
    if (msg.sender == admin) {
      address payable dex = selectDex(tk1, tk2);
      dex.transfer(msg.value);
      uint gasprice = Dex(dex).getConfigUint(ConfigKey.gasprice); //current price per gas spent in offer fails
      uint available = Dex(dex).balanceOf(address(this)) - (gasprice * execGas); //enabling delegatecall
      require(available >= 0, "Insufficient funds to push offer."); //better fail early
      Dex(dex).newOffer(wants, gives, execGas, position); // discards offerId
    }
  }

  function pullOffer(
    address tk1,
    address tk2,
    uint offerId
  ) external {
    if (msg.sender == admin) {
      address payable dex = selectDex(tk1, tk2);
      uint releasedWei = Dex(dex).cancelOffer(offerId); // Dex will release provision of offerId
      Dex(dex).withdraw(releasedWei);
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
    uint,
    uint,
    uint,
    uint
  ) external view override {
    //making sure execution is sent by the corresponding dex
    require((msg.sender == DEXAB) || (msg.sender == DEXBA));
  }
}
