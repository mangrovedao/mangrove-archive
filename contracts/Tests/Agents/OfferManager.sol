// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../../Dex.sol";
import "../../interfaces.sol";
import "../../DexCommon.sol";
import "hardhat/console.sol";
import {DexCommon as DC} from "../Toolbox/Display.sol";

contract OfferManager is IMaker {
  // erc_addr -> owner_addr -> balance
  Dex dex;
  mapping(uint => address) owners;
  uint constant gas_to_execute = 100_000;

  constructor(Dex _dex) {
    dex = _dex;
  }

  function makerHandoff(IMaker.Handoff calldata handoff)
    external
    pure
    override
  {}

  // Maker side execute for residual offer

  function makerTrade(IMaker.Trade calldata trade)
    external
    override
    returns (bytes32)
  {
    require(msg.sender == address(dex));

    emit Execute(trade.takerWants, trade.takerGives, trade.offerId);

    // if residual of offerId is < dust, offer will be removed and dust lost
    // also freeWeil[this] will increase, offerManager may chose to give it back to owner
    try IERC20(trade.base).transfer(trade.taker, trade.takerWants) {
      address owner = owners[trade.offerId];
      try IERC20(trade.quote).transfer(owner, trade.takerGives) {
        return "OfferManager/transferOK";
      } catch {
        return "transferToOwnerFail";
      }
    } catch {
      return "transferToDexFail";
    }
  }

  function order(
    address base,
    address quote,
    uint wants,
    uint gives
  ) external payable {
    console.log("In Offer Manager");

    DC.Config memory config = dex.config(base, quote);

    IERC20(quote).transferFrom(msg.sender, address(this), gives); // OfferManager must be approved by sender

    console.log("Manager has received quote funds");

    uint balBase = IERC20(base).balanceOf(address(this));
    dex.simpleMarketOrder(base, quote, wants, gives); // OfferManager might collect provisions of failing offers

    console.log("Manager has finished market Order to DEX(A,B)");

    uint residual_w = wants - (IERC20(base).balanceOf(address(this)) - balBase);
    uint residual_g = (gives * residual_w) / wants;

    require(
      msg.value >= gas_to_execute * config.gasprice,
      "Insufficent funds to delegate order"
    ); //TODO overflow issues
    (bool success, ) = address(dex).call{value: msg.value}("");

    require(success, "provision dex failed");
    uint residual_ofr =
      dex.newOffer(quote, base, residual_w, residual_g, gas_to_execute, 0);
    owners[residual_ofr] = msg.sender;
  }
}
