// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
// Encode structs
pragma experimental ABIEncoderV2;

import "../Agents/TestTaker.sol";
import "../Agents/MakerDeployer.sol";
import "../Agents/TestMoriartyMaker.sol";
import "../Agents/TestToken.sol";

import "./TestEvents.sol";
import "./Display.sol";

library TestUtils {
  struct Balances {
    uint dexBalanceWei;
    uint dexBalanceFees;
    uint takerBalanceA;
    uint takerBalanceB;
    uint takerBalanceWei;
    uint[] makersBalanceA;
    uint[] makersBalanceB;
    uint[] makersBalanceWei;
  }
  enum Info {makerWants, makerGives, nextId, gasreq, gasprice}

  function getReason(bytes memory returnData)
    internal
    pure
    returns (string memory reason)
  {
    /* returnData for a revert(reason) is the result of 
       abi.encodeWithSignature("Error(string)",reason)
       but abi.decode assumes the first 4 bytes are padded to 32
       so we repad them. See:
       https://github.com/ethereum/solidity/issues/6012
     */
    bytes memory pointer = abi.encodePacked(bytes28(0), returnData);
    uint len = returnData.length - 4;
    assembly {
      pointer := add(32, pointer)
      mstore(pointer, len)
    }
    reason = abi.decode(pointer, (string));
  }

  function isEmptyOB(
    Dex dex,
    address base,
    address quote
  ) internal view returns (bool) {
    (DC.Offer memory offer, ) =
      dex.getOfferInfo(base, quote, dex.getBest(base, quote), true);
    return !DC.isLive(offer);
  }

  function adminOf(Dex dex) internal view returns (address) {
    return dex.admin();
  }

  function getFee(
    Dex dex,
    address base,
    address quote,
    uint price
  ) internal view returns (uint) {
    return ((price * dex.config(base, quote).local.fee) / 10000);
  }

  function getProvision(
    Dex dex,
    address base,
    address quote,
    uint gasreq
  ) internal view returns (uint) {
    DC.Config memory config = dex.config(base, quote);
    return ((gasreq + config.global.gasbase) *
      uint(config.global.gasprice) *
      10**9);
  }

  function getOfferInfo(
    Dex dex,
    address base,
    address quote,
    Info infKey,
    uint offerId
  ) internal view returns (uint) {
    (DC.Offer memory offer, DC.OfferDetail memory offerDetail) =
      dex.getOfferInfo(base, quote, offerId, true);
    if (infKey == Info.makerWants) {
      return offer.wants;
    }
    if (infKey == Info.makerGives) {
      return offer.gives;
    }
    if (infKey == Info.nextId) {
      return offer.next;
    }
    if (infKey == Info.gasreq) {
      return offerDetail.gasreq;
    } else {
      return offer.gasprice;
    }
  }

  function hasOffer(
    Dex dex,
    address base,
    address quote,
    uint offerId
  ) internal view returns (bool) {
    return (getOfferInfo(dex, base, quote, Info.makerGives, offerId) > 0);
  }

  function makerOf(
    Dex dex,
    address base,
    address quote,
    uint offerId
  ) internal view returns (address) {
    (, DC.OfferDetail memory od) = dex.getOfferInfo(base, quote, offerId, true);
    return od.maker;
  }
}

// Pretest libraries are for deploying large contracts independently.
// Otherwise bytecode can be too large. See EIP 170 for more on size limit:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md

library TokenSetup {
  function setup(string memory name, string memory ticker)
    external
    returns (TestToken)
  {
    return new TestToken(address(this), name, ticker);
  }
}

library DexSetup {
  function setup(TestToken base, TestToken quote) external returns (Dex dex) {
    TestEvents.not0x(address(base));
    TestEvents.not0x(address(quote));
    dex = new NormalDex({gasprice: 40, gasbase: 30_000, gasmax: 1_000_000});

    dex.activate(address(base), address(quote), 0, 100);
    dex.activate(address(quote), address(base), 0, 100);

    return dex;
  }
}

library InvertedDexSetup {
  function setup(TestToken base, TestToken quote) external returns (Dex dex) {
    TestEvents.not0x(address(base));
    TestEvents.not0x(address(quote));
    dex = new InvertedDex({gasprice: 40, gasbase: 30_000, gasmax: 1_000_000});

    dex.activate(address(base), address(quote), 0, 100);
    dex.activate(address(quote), address(base), 0, 100);

    return dex;
  }
}

library MakerSetup {
  function setup(
    Dex dex,
    address base,
    address quote,
    bool shouldFail
  ) external returns (TestMaker) {
    TestMaker tm = new TestMaker(dex, IERC20(base), IERC20(quote));
    tm.shouldFail(shouldFail);
    return tm;
  }

  function setup(
    Dex dex,
    address base,
    address quote
  ) external returns (TestMaker) {
    return new TestMaker(dex, ERC20(base), ERC20(quote));
  }
}

library MakerDeployerSetup {
  function setup(
    Dex dex,
    address base,
    address quote
  ) external returns (MakerDeployer) {
    TestEvents.not0x(address(dex));
    return (new MakerDeployer(dex, base, quote));
  }
}

library TakerSetup {
  function setup(
    Dex dex,
    address base,
    address quote
  ) external returns (TestTaker) {
    TestEvents.not0x(address(dex));
    return new TestTaker(dex, ERC20(base), ERC20(quote));
  }
}
