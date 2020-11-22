// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
import "./Passthrough.sol";
import "../../interfaces.sol";
import "../../Dex.sol";

contract TestMoriartyMaker is IMaker, Passthrough {
  Dex dex;
  bool succeed;
  uint dummy;

  constructor(Dex _dex) {
    dex = _dex;
    succeed = true;
  }

  function execute(
    uint,
    uint,
    uint,
    uint offerId
  ) public override {
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
    dex.newOffer(wants, gives, gasreq, pivotId);
    dex.newOffer(wants, gives, gasreq, pivotId);
    dex.newOffer(wants, gives, gasreq, pivotId);
    dex.newOffer(wants, gives, gasreq, pivotId);
    uint density = dex.getConfigUint(ConfigKey.density);
    uint gasbase = dex.getConfigUint(ConfigKey.gasbase);
    dummy = dex.newOffer(0, density * (gasbase + 1), 1, 0); //dummy offer
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
