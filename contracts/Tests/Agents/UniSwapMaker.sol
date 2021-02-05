// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;

import "../../ERC20.sol";
import "../../Dex.sol";

// Dex must be provisioned in the name of UniSwapMaker
// UniSwapMaker must have ERC20 credit in tk0 and tk1 and these credits should not be shared (since contract is memoryless)
contract UniSwapMaker is IMaker {
  Dex dex;
  address private admin;
  uint gasreq = 80_000;
  uint share; // [1,100] for 1/1 to 1/100
  uint fee; // per 1000
  uint ofr0;
  uint ofr1;

  constructor(
    Dex _dex,
    uint _share,
    uint _fee
  ) {
    require(_fee < 1000 && _share > 1, "Invalid parameters");
    admin = msg.sender;
    dex = _dex; // FMD or FTD
    share = _share;
    fee = _fee;
  }

  receive() external payable {}

  function setParams(uint _fee, uint _share) external {
    require(_fee < 1000 && _share > 1, "Invalid parameters");
    if (msg.sender == admin) {
      fee = _fee;
      share = _share;
    }
  }

  function withdraw(address recipient, uint amount) external {
    if (msg.sender == admin) {
      bool noRevert;
      (noRevert, ) = address(recipient).call{value: amount}("");
      require(noRevert);
    }
  }

  function makerTrade(DC.SingleOrder calldata order)
    external
    override
    returns (bytes32)
  {
    require(msg.sender == address(dex), "Illegal call");
    emit Execute(
      msg.sender,
      order.base, // takerWants
      order.quote, // takerGives
      order.offerId,
      order.wants,
      order.gives
    );
  }

  // newPrice(makerWants,makerGives)
  function newPrice(uint pool0, uint pool1) internal view returns (uint, uint) {
    uint newGives = pool1 / share; // share = 100 for 1%
    uint x = (newGives * pool0) / (pool1 - newGives); // forces newGives < poolGives
    uint newWants = (1000 * x) / (1000 - fee); // fee < 1000
    return (newWants, newGives);
  }

  function newMarket(address tk0, address tk1) public {
    ERC20(tk0).approve(address(dex), 2**256 - 1);
    ERC20(tk1).approve(address(dex), 2**256 - 1);

    uint pool0 = ERC20(tk0).balanceOf(address(this));
    uint pool1 = ERC20(tk1).balanceOf(address(this));

    (uint wants0, uint gives1) = newPrice(pool0, pool1);
    (uint wants1, uint gives0) = newPrice(pool1, pool0);
    ofr0 = dex.newOffer(tk0, tk1, wants0, gives1, gasreq, 0, 0);
    ofr1 = dex.newOffer(tk1, tk0, wants1, gives0, gasreq, 0, 0); // natural OB
  }

  function makerPosthook(DC.SingleOrder calldata order, DC.OrderResult calldata)
    external
    override
  {
    // taker has paid maker
    require(msg.sender == address(dex)); // may not be necessary
    uint pool0 = ERC20(order.quote).balanceOf(address(this)); // pool0 has increased
    uint pool1 = ERC20(order.base).balanceOf(address(this)); // pool1 has decreased

    (uint newWants, uint newGives) = newPrice(pool0, pool1);

    dex.updateOffer(
      order.base,
      order.quote,
      newWants,
      newGives,
      gasreq,
      0, // gasprice
      0, // best pivot
      order.offerId // the offer that was executed
    );
    // for all pairs in opposite Dex:
    uint OFR = ofr0;
    if (order.offerId == ofr0) {
      OFR = ofr1;
    }

    (newWants, newGives) = newPrice(pool1, pool0);
    dex.updateOffer(
      order.quote,
      order.base,
      newWants,
      newGives,
      gasreq,
      0,
      OFR,
      OFR
    );
  }
}
