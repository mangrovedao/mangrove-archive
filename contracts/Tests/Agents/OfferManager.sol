// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../../Dex.sol";
import "../../interfaces.sol";
import "../../DexCommon.sol";
import "hardhat/console.sol";
import "../Toolbox/Display.sol";
import {DexCommon as DC} from "../Toolbox/Display.sol";

contract OfferManager is IMaker, ITaker {
  // erc_addr -> owner_addr -> balance
  Dex dex;
  Dex invDex;
  address caller_id;
  // dex_addr -> base_addr -> quote_addr -> offerId -> owner
  mapping(address => mapping(address => mapping(address => mapping(uint => address)))) owners;
  uint constant gas_to_execute = 100_000;

  constructor(Dex _dex, Dex _inverted) {
    dex = _dex;
    invDex = _inverted;
  }

  //posthook data:
  //base: orp.base,
  // quote: orp.quote,
  // takerWants: takerWants,
  // takerGives: takerGives,
  // offerId: offerId,
  // offerDeleted: toDelete

  function takerTrade(
    //NB this is not called if dex is not a flashTaker dex
    address base,
    address quote,
    uint netReceived,
    uint shouldGive
  ) external override {
    if (msg.sender == address(invDex)) {
      ITaker(caller_id).takerTrade(base, quote, netReceived, shouldGive); // taker will find funds
      IERC20(quote).transferFrom(caller_id, address(this), shouldGive); // ready to be withdawn by Dex
    }
  }

  function makerPosthook(IMaker.Posthook calldata posthook) external override {
    if (msg.sender == address(invDex)) {
      //should have received funds by now
      address owner =
        owners[msg.sender][posthook.base][posthook.quote][posthook.offerId];
      require(owner != address(0), "Unkown owner");
      IERC20(posthook.quote).transfer(owner, posthook.takerGives);
    }
  }

  // Maker side execute for residual offer

  function makerTrade(IMaker.Trade calldata trade)
    external
    override
    returns (bytes32)
  {
    emit Execute(
      msg.sender,
      trade.base,
      trade.quote,
      trade.offerId,
      trade.takerWants,
      trade.takerGives
    );
    if (msg.sender == address(dex)) {
      // if residual of offerId is < dust, offer will be removed and dust lost
      // also freeWeil[this] will increase, offerManager may chose to give it back to owner
      try IERC20(trade.base).transfer(trade.taker, trade.takerWants) {
        address owner =
          owners[address(dex)][trade.base][trade.quote][trade.offerId];
        require(owner != address(0), "Unkown owner");
        try IERC20(trade.quote).transfer(owner, trade.takerGives) {
          return "OfferManager/transferOK";
        } catch {
          return "transferToOwnerFail";
        }
      } catch {
        return "transferToTakerFail";
      }
    } else {
      require(msg.sender == address(invDex), "Invalid msg.sender");
      try IERC20(trade.base).transfer(trade.taker, trade.takerWants) {} catch {
        return "transferToTakerFail";
      }
    }
  }

  //marketOrder (base,quote) + NewOffer(quote,base)
  function order(
    address base,
    address quote,
    uint wants,
    uint gives,
    bool is_flashTaker,
    bool invertedResidual
  ) external payable {
    Dex DEX;
    if (!is_flashTaker) {
      DEX = dex;
    } else {
      DEX = invDex;
    }
    DC.Config memory config = DEX.config(base, quote);

    caller_id = msg.sender; // this should come with a reentrancy lock
    if (!is_flashTaker) {
      // else caller_id will be called when takerTrade is called by Dex
      IERC20(quote).transferFrom(msg.sender, address(this), gives); // OfferManager must be approved by sender
    }
    IERC20(quote).approve(address(DEX), 100 ether); // to pay maker
    IERC20(base).approve(address(DEX), 100 ether); // takerfee

    (uint netReceived, ) = DEX.simpleMarketOrder(base, quote, wants, gives); // OfferManager might collect provisions of failing offers

    try IERC20(base).transfer(msg.sender, netReceived) {
      uint residual_w = wants - netReceived;
      uint residual_g = (gives * residual_w) / wants;
      require(
        msg.value >= gas_to_execute * uint(config.global.gasprice) * 10**9,
        "Insufficent funds to delegate order"
      ); //not checking overflow issues
      (bool success, ) = address(dex).call{value: msg.value}("");

      require(success, "provision dex failed");

      uint residual_ofr =
        DEX.newOffer(quote, base, residual_w, residual_g, gas_to_execute, 0, 0);
      owners[address(DEX)][quote][base][residual_ofr] = msg.sender;
    } catch {
      require(false, "Failed to send market order money to owner");
    }
  }
}
