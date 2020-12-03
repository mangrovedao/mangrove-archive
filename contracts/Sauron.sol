// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import {DexCommon as DC, DexEvents} from "./DexCommon.sol";
import "./lib/HasAdmin.sol";
import "./interfaces.sol";

/* The Sauron contract contains all the configuration parameters for all dexes. Parameters `gasprice`, `gasbase` and `gasmax` are global to all dexes, while each dex has its own `fee` and `density`. */
contract Sauron is HasAdmin, ISauron {
  /* Parameters in `Global` are the same for all dexes. Paremeters in `Local` are specific to each dex. See `DexCommon.sol` for information about each configuration parameter. */
  struct Global {
    uint48 gasprice;
    uint24 gasbase;
    uint24 gasmax;
  }

  struct Local {
    uint16 fee;
    uint32 density;
  }

  constructor(
    uint _gasprice,
    uint _gasbase,
    uint _gasmax
  ) HasAdmin() {
    gasprice(_gasprice);
    gasbase(_gasbase);
    gasmax(_gasmax);
  }

  Global private _global;

  mapping(address => Local) locals;

  function config(address dex)
    external
    view
    override
    returns (DC.Config memory)
  {
    Global memory global = _global;
    Local memory local = locals[dex];

    return
      DC.Config({
        fee: /* By default, fee is 0, which is fine. */
        local.fee,
        density: /* A density of 0 breaks a Dex, and without a call to `density(value)`, density will be 0. So we return a density of 1 by default. */
        local.density == 0 ? 1 : local.density,
        gasprice: global.gasprice,
        gasbase: global.gasbase,
        gasmax: global.gasmax
      });
  }

  /* # Configuration access */
  //+clear+
  /* Setter functions for configuration, called by `setConfig` which also exists in Dex. Overloaded by the type of the `value` parameter. See `DexCommon.sol` for more on the `config` and `key` parameters. */

  /* ## Locals */

  /* ### `fee` */
  function fee(address dex, uint value) public override adminOnly {
    /* `fee` is in basis points, i.e. in percents of a percent. */
    require(value <= 10000, "dex/config/fee/IsBps"); // at most 14 bits
    locals[dex].fee = uint16(value);
    emit DexEvents.SetFee(dex, value);
  }

  /* ### `density` */
  function density(address dex, uint value) public override adminOnly {
    /* `density > 0` ensures various invariants -- this documentation explains each time how it is relevant. */
    require(value > 0, "dex/config/density/>0");
    /* Checking the size of `density` is necessary to prevent overflow when `density` is used in calculations. */
    require(uint32(value) == value);
    //+clear+
    locals[dex].density = uint32(value);
    emit DexEvents.SetDustPerGasWanted(dex, value);
  }

  /* ## Globals */
  /* ### `gasprice` */
  function gasprice(uint value) public override adminOnly {
    /* Checking the size of `gasprice` is necessary to prevent a) data loss when `gasprice` is copied to an `OfferDetail` struct, and b) overflow when `gasprice` is used in calculations. */
    require(uint48(value) == value, "dex/config/gasprice/48bits");
    //+clear+
    _global.gasprice = uint48(value);
    emit DexEvents.SetGasprice(value);
  }

  /* ### `gasbase` */
  function gasbase(uint value) public override adminOnly {
    /* `gasbase > 0` ensures various invariants -- this documentation explains how each time it is relevant */
    require(value > 0, "dex/config/gasbase/>0");
    /* Checking the size of `gasbase` is necessary to prevent a) data loss when `gasbase` is copied to an `OfferDetail` struct, and b) overflow when `gasbase` is used in calculations. */
    require(uint24(value) == value, "dex/config/gasbase/24bits");
    //+clear+
    _global.gasbase = uint24(value);
    emit DexEvents.SetGasbase(value);
  }

  /* ### `gasmax` */
  function gasmax(uint value) public override adminOnly {
    /* Since any new `gasreq` is bounded above by `config.gasmax`, this check implies that all offers' `gasreq` is 24 bits wide at most. */
    require(uint24(value) == value, "dex/config/gasmax/24bits");
    //+clear+
    _global.gasmax = uint24(value);
    emit DexEvents.SetGasmax(value);
  }
}
