// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

interface ERC20 {
  function approve(address dexAddr, uint256 amount) external returns (bool);
}

interface Dex {
  function REQ_TOKEN() external returns (address);

  function OFR_TOKEN() external returns (address);

  function newOrder(
    uint256 makerWants,
    uint256 makerGives,
    uint256 gasWanted,
    uint256 pivotId
  ) external;

  function balanceOf(address maker) external returns (uint256);

  function best() external returns (uint256);

  function penaltyPerGas() external returns (uint256);
}

contract Maker {
  address immutable REQ_TOKEN;
  address immutable OFR_TOKEN;
  address payable immutable DEX; // Address of a (REQ_TOKEN,OFR_TOKEN) DEX
  address private immutable THIS;
  uint32 private execGas;

  constructor(
    address reqToken,
    address ofrToken,
    address payable dex2
  ) {
    require(Dex(dex2).REQ_TOKEN() == reqToken);
    require(Dex(dex2).OFR_TOKEN() == ofrToken);
    execGas = 1000;
    REQ_TOKEN = reqToken;
    OFR_TOKEN = ofrToken;
    DEX = dex2;
    THIS = address(this);
  }

  function setExecGas(uint256 cost) external {
    require(msg.sender == THIS);
    execGas = uint32(cost);
  }

  function pushOrder(
    uint256 wants,
    uint256 gives,
    uint256 position
  ) external payable {
    DEX.transfer(msg.value);
    uint256 penaltyPerGas = Dex(DEX).penaltyPerGas(); //current price per gas spent in offer fails
    uint256 available = Dex(DEX).balanceOf(address(this)) -
      (penaltyPerGas * execGas); //enabling delegatecall
    require(available >= 0, "Insufficient provision to push order.");
    Dex(DEX).newOrder(wants, gives, execGas, position);
  }

  function execute(
    uint256 takerWants,
    uint256 takerGives,
    uint64 orderPenaltyPerGas
  ) external {
    require(msg.sender == DEX);
    //giving allowance to DEX in order to credit taker
    bool success = ERC20(OFR_TOKEN).approve(DEX, takerWants);
    require(success, "Failed to give allowance.");
  }
}
