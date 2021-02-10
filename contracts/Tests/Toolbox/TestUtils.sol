// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
// Encode structs
pragma abicoder v2;

import "../Agents/TestTaker.sol";
import "../Agents/MakerDeployer.sol";
import "../Agents/TestMoriartyMaker.sol";
import "../Agents/TestToken.sol";

import "./TestEvents.sol";
import "./Display.sol";

import "../../DexIt.sol";

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
    return DexIt.getBest(dex, base, quote) == 0;
  }

  function adminOf(Dex dex) internal view returns (address) {
    return dex.governance();
  }

  function getFee(
    Dex dex,
    address base,
    address quote,
    uint price
  ) internal returns (uint) {
    return ((price * dex.config(base, quote).local.fee) / 10000);
  }

  function getProvision(
    Dex dex,
    address base,
    address quote,
    uint gasreq
  ) internal returns (uint) {
    DC.Config memory config = dex.config(base, quote);
    return ((gasreq + config.local.gasbase) *
      uint(config.global.gasprice) *
      10**9);
  }

  function getProvision(
    Dex dex,
    address base,
    address quote,
    uint gasreq,
    uint gasprice
  ) internal returns (uint) {
    DC.Config memory config = dex.config(base, quote);
    uint _gp;
    if (config.global.gasprice > gasprice) {
      _gp = uint(config.global.gasprice);
    } else {
      _gp = gasprice;
    }
    return ((gasreq + config.local.gasbase) * _gp * 10**9);
  }

  function getOfferInfo(
    Dex dex,
    address base,
    address quote,
    Info infKey,
    uint offerId
  ) internal view returns (uint) {
    (bool exists, DC.Offer memory offer, DC.OfferDetail memory offerDetail) =
      DexIt.getOfferInfo(dex, base, quote, offerId);
    if (!exists) {
      return 0;
    }
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
    (, , DC.OfferDetail memory od) =
      DexIt.getOfferInfo(dex, base, quote, offerId);
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
    dex = new FMD({gasprice: 40, gasmax: 1_000_000});

    dex.activate(address(base), address(quote), 0, 100, 80_000);
    dex.activate(address(quote), address(base), 0, 100, 80_000);

    return dex;
  }

  function setup(
    TestToken base,
    TestToken quote,
    bool inverted
  ) external returns (Dex dex) {
    TestEvents.not0x(address(base));
    TestEvents.not0x(address(quote));
    if (inverted) {
      dex = new FTD({gasprice: 40, gasmax: 1_000_000});

      dex.activate(address(base), address(quote), 0, 100, 80_000);
      dex.activate(address(quote), address(base), 0, 100, 80_000);

      return dex;
    } else {
      dex = new FMD({gasprice: 40, gasmax: 1_000_000});

      dex.activate(address(base), address(quote), 0, 100, 80_000);
      dex.activate(address(quote), address(base), 0, 100, 80_000);

      return dex;
    }
  }
}

library MakerSetup {
  function setup(
    Dex dex,
    address base,
    address quote,
    uint failer // 1 shouldFail, 2 shouldRevert
  ) external returns (TestMaker) {
    TestMaker tm = new TestMaker(dex, IERC20(base), IERC20(quote));
    tm.shouldFail(failer == 1);
    tm.shouldRevert(failer == 2);
    return (tm);
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
