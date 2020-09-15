// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

interface ERC20 {
  function approve(address dexAddr, uint256 amount) external returns (bool);

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);
}

interface Dex {
  function REQ_TOKEN() external returns (address);

  function OFR_TOKEN() external returns (address);

  function newOrder(
    uint256 makerWants,
    uint256 makerGives,
    uint256 gasWanted,
    uint256 pivotId
  ) external returns (uint256);

  function balanceOf(address maker) external returns (uint256);

  function penaltyPerGas() external returns (uint256);

  function withdraw(uint256) external;
}

contract Maker {
  address immutable A_TOKEN;
  address immutable B_TOKEN;
  address payable immutable DEXAB; // Address of a (A,B) DEX
  address payable immutable DEXBA; // Address of a (B,A) DEX
  address private admin;
  uint256 private execGas;
  mapping(uint256 => bool) orderStatus;

  constructor(
    address tk_A,
    address tk_B,
    address payable dexAB,
    address payable dexBA
  ) {
    require(
      (Dex(dexAB).REQ_TOKEN() == tk_A) && (Dex(dexAB).OFR_TOKEN() == tk_B)
    );
    require(
      (Dex(dexBA).REQ_TOKEN() == tk_B) && (Dex(dexBA).OFR_TOKEN() == tk_A)
    );
    bool successAB = ERC20(tk_A).approve(dexAB, 2**256 - 1);
    bool successBA = ERC20(tk_B).approve(dexBA, 2**256 - 1);
    require(successAB && successBA, "Failed to give allowance.");

    execGas = 1000;
    A_TOKEN = tk_A;
    B_TOKEN = tk_B;
    DEXAB = dexAB;
    DEXBA = dexBA;
    admin = msg.sender;
  }

  function acceptOrder(uint256 orderId) internal {
    require(orderStatus[orderId]); // Throws if orderId is not in the whitelist
    delete (orderStatus[orderId]); // sets status of orderId to false
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
    address payable dex = selectDex(tk1, tk2);
    dex.transfer(msg.value);
    uint256 penaltyPerGas = Dex(dex).penaltyPerGas(); //current price per gas spent in offer fails
    uint256 available = Dex(dex).balanceOf(address(this)) -
      (penaltyPerGas * execGas); //enabling delegatecall
    require(available >= 0, "Insufficient funds to push order."); //better fail early
    uint256 orderId = Dex(dex).newOrder(wants, gives, execGas, position);
    orderStatus[orderId] = true;
  }

  receive() external payable {}

  function transferWEI(uint256 amount, address payable receiver) external {
    if (msg.sender == admin) {
      receiver.transfer(amount);
    }
  }

  function transferToken(
    address token,
    address from,
    address to,
    uint256 value
  ) external returns (bool) {
    if (msg.sender == admin) {
      bytes memory cd = abi.encodeWithSelector(
        ERC20(token).transferFrom.selector,
        from,
        to,
        value
      );
      (bool success, bytes memory data) = token.call(cd);
      return (success && (data.length == 0 || abi.decode(data, (bool))));
    } else {
      return false;
    }
  }

  function execute(
    uint256 orderId,
    uint256,
    uint256,
    uint256
  ) external {
    acceptOrder(orderId);
  }
}
