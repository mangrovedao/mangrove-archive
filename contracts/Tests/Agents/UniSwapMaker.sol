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
  uint gasreq = 70_000;
  uint share;
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
  function newPrice(ERC20 tk, ERC20 _tk) internal view returns (uint, uint) {
    uint poolWants = tk.balanceOf(address(this));
    uint poolGives = _tk.balanceOf(address(this));

    uint newGives = poolGives / share; // share = 100 for 1%
    uint x = (newGives * poolWants) / (poolGives - newGives); // forces newGives < poolGives
    uint newWants = (1000 * x) / (1000 - fee); // fee < 1000
    return (newWants, newGives);
  }

  function newOffer(address tk0, address tk1) public {
    ERC20(tk0).approve(address(dex), 2**256 - 1);
    ERC20(tk1).approve(address(dex), 2**256 - 1);

    (uint wants0, uint gives1) = newPrice(ERC20(tk0), ERC20(tk1));
    (uint wants1, uint gives0) = newPrice(ERC20(tk1), ERC20(tk0)); // natural pair
    ofr0 = dex.newOffer(tk0, tk1, wants0, gives1, gasreq, 0, 0);
    ofr1 = dex.newOffer(tk1, tk0, wants1, gives0, gasreq, 0, 0); // natural OB
  }

  function makerPosthook(DC.SingleOrder calldata order, DC.OrderResult calldata)
    external
    override
  {
    // taker has paid maker
    require(msg.sender == address(dex));
    (uint newWants, uint newGives) =
      newPrice(ERC20(order.quote), ERC20(order.base));

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

    (newWants, newGives) = newPrice(ERC20(order.base), ERC20(order.quote));
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
