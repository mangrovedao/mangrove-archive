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
    REQ_TOKEN = reqToken;
    OFR_TOKEN = ofrToken;
    DEX = dex2;
    THIS = address(this);
  }

  function execute(
    uint256 takerWants,
    uint256 takerGives,
    uint64 orderPenaltyPerGas
  ) external {
    require(msg.sender == DEX);
    //giving allowance to DEX in order to credit taker
    require(ERC20(OFR_TOKEN).approve(DEX, takerWants));
  }
}
