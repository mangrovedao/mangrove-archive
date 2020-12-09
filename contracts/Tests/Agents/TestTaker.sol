// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "../../interfaces.sol";
import "../../Dex.sol";

contract TestTaker is ITaker {
  Dex dex;
  address atk;
  address btk;

  constructor(
    Dex _dex,
    address _atk,
    address _btk
  ) {
    dex = _dex;
    atk = _atk;
    btk = _btk;
  }

  receive() external payable {}

  function approve(IERC20 token, uint amount) external {
    token.approve(address(dex), amount);
  }

  function take(uint offerId, uint takerWants)
    external
    override
    returns (bool success)
  {
    //uint taken = TestEvents.min(makerGives, takerWants);
    success = dex.snipe(atk, btk, offerId, takerWants);
    //return taken;
  }

  function marketOrder(uint wants, uint gives) external override {
    dex.simpleMarketOrder(atk, btk, wants, gives);
  }

  function marketOrderWithFail(
    uint wants,
    uint gives,
    uint punishLength,
    uint offerId
  ) external returns (uint[2][] memory) {
    return (dex.marketOrder(atk, btk, wants, gives, punishLength, offerId));
  }

  function snipesAndRevert(uint[2][] calldata targets, uint punishLength)
    external
  {
    dex.punishingSnipes(atk, btk, targets, punishLength);
  }

  function marketOrderAndRevert(
    uint fromOfferId,
    uint takerWants,
    uint takerGives,
    uint punishLength
  ) external {
    dex.punishingMarketOrder(
      atk,
      btk,
      fromOfferId,
      takerWants,
      takerGives,
      punishLength
    );
  }
}
