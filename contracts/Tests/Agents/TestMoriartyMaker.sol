// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "./Passthrough.sol";
import "../../interfaces.sol";
import "../../Dex.sol";

contract TestMoriartyMaker is IMaker, Passthrough {
  Dex dex;
  address atk;
  address btk;
  bool succeed;
  uint dummy;

  constructor(
    Dex _dex,
    address _atk,
    address _btk
  ) {
    dex = _dex;
    atk = _atk;
    btk = _btk;
    succeed = true;
  }

  function execute(
    address,
    address,
    uint,
    uint,
    uint,
    uint offerId
  ) public override {
    //console.log("Executing offer %d", offerId);

    assert(succeed);
    if (offerId == dummy) {
      succeed = false;
    }
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public {
    dex.newOffer(atk, btk, wants, gives, gasreq, pivotId);
    dex.newOffer(atk, btk, wants, gives, gasreq, pivotId);
    dex.newOffer(atk, btk, wants, gives, gasreq, pivotId);
    dex.newOffer(atk, btk, wants, gives, gasreq, pivotId);
    uint density = dex.config(atk, btk).density;
    uint gasbase = dex.config(atk, btk).gasbase;
    dummy = dex.newOffer({
      ofrToken: atk,
      reqToken: btk,
      wants: 1,
      gives: density * (gasbase + 10000),
      gasreq: 10000,
      pivotId: 0
    }); //dummy offer
  }

  function provisionDex(uint amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success);
  }

  function approve(IERC20 token, uint amount) public {
    token.approve(address(dex), amount);
  }

  receive() external payable {}
}
