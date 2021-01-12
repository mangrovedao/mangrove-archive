// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../../Dex.sol";
import "../../interfaces.sol";
import "../../DexCommon.sol";
import "hardhat/console.sol";
import "../Toolbox/Display.sol";
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
    DC.Config memory config = dex.config(base, quote);

    IERC20(quote).transferFrom(msg.sender, address(this), gives); // OfferManager must be approved by sender
    IERC20(quote).approve(address(dex), 100 ether); // to pay maker
    IERC20(base).approve(address(dex), 100 ether); // takerfee

    (uint netReceived, uint totalGave) =
      dex.simpleMarketOrder(base, quote, wants, gives); // OfferManager might collect provisions of failing offers

    try IERC20(base).transfer(msg.sender, netReceived) {
      uint residual_w = wants - netReceived;
      uint residual_g = (gives * residual_w) / wants;
      require(
        msg.value >= gas_to_execute * config.gasprice,
        "Insufficent funds to delegate order"
      ); //TODO overflow issues
      (bool success, ) = address(dex).call{value: msg.value}("");

      require(success, "provision dex failed");
      uint residual_ofr =
        dex.newOffer(quote, base, residual_w, residual_g, gas_to_execute, 0, 0);
      owners[residual_ofr] = msg.sender;
    } catch {
      require(false, "Failed to send market order money to owner");
    }
  }
}
