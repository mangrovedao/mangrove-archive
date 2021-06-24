// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;
import {MgvEvents} from "./MgvLib.sol";
import {MgvRoot} from "./MgvRoot.sol";

contract MgvGovernable is MgvRoot {
  /* The `governance` address. Governance is the only address that can configure parameters. */
  address public governance;

  constructor(uint _gasprice, uint gasmax) MgvRoot() {
    emit MgvEvents.NewMgv();

    /* Initialize governance. */
    _setGovernance(msg.sender);

    /* Initialize vault to sender's address, and set initial gasprice and gasmax. */
    setVault(msg.sender);
    setGasprice(_gasprice);
    setGasmax(gasmax);
  }

  /* # Set configuration and Mangrove state */

  /* ## Locals */
  /* ### `active` */
  function activate(
    address base,
    address quote,
    uint fee,
    uint density,
    uint overhead_gasbase,
    uint offer_gasbase
  ) public {
    authOnly();
    locals[base][quote] = $$(set_local("locals[base][quote]", [["active", 1]]));
    emit MgvEvents.SetActive(base, quote, true);
    setFee(base, quote, fee);
    setDensity(base, quote, density);
    setGasbase(base, quote, overhead_gasbase, offer_gasbase);
  }

  function deactivate(address base, address quote) public {
    authOnly();
    locals[base][quote] = $$(set_local("locals[base][quote]", [["active", 0]]));
    emit MgvEvents.SetActive(base, quote, false);
  }

  /* ### `fee` */
  function setFee(
    address base,
    address quote,
    uint fee
  ) public {
    authOnly();
    /* `fee` is in basis points, i.e. in percents of a percent. */
    require(fee <= 500, "mgv/config/fee/<=500"); // at most 5%
    locals[base][quote] = $$(
      set_local("locals[base][quote]", [["fee", "fee"]])
    );
    emit MgvEvents.SetFee(base, quote, fee);
  }

  /* ### `density` */
  /* Useless if `global.useOracle != 0` */
  function setDensity(
    address base,
    address quote,
    uint density
  ) public {
    authOnly();
    /* Checking the size of `density` is necessary to prevent overflow when `density` is used in calculations. */
    require(uint32(density) == density, "mgv/config/density/32bits");
    //+clear+
    locals[base][quote] = $$(
      set_local("locals[base][quote]", [["density", "density"]])
    );
    emit MgvEvents.SetDensity(base, quote, density);
  }

  /* ### `gasbase` */
  function setGasbase(
    address base,
    address quote,
    uint overhead_gasbase,
    uint offer_gasbase
  ) public {
    authOnly();
    /* Checking the size of `*_gasbase` is necessary to prevent a) data loss when `*_gasbase` is copied to an `OfferDetail` struct, and b) overflow when `*_gasbase` is used in calculations. */
    require(
      uint24(overhead_gasbase) == overhead_gasbase,
      "mgv/config/overhead_gasbase/24bits"
    );
    require(
      uint24(offer_gasbase) == offer_gasbase,
      "mgv/config/offer_gasbase/24bits"
    );
    //+clear+
    locals[base][quote] = $$(
      set_local(
        "locals[base][quote]",
        [
          ["offer_gasbase", "offer_gasbase"],
          ["overhead_gasbase", "overhead_gasbase"]
        ]
      )
    );
    emit MgvEvents.SetGasbase(base, quote, overhead_gasbase, offer_gasbase);
  }

  /* ## Globals */
  /* ### `kill` */
  function kill() public {
    authOnly();
    global = $$(set_global("global", [["dead", 1]]));
    emit MgvEvents.Kill();
  }

  /* ### `gasprice` */
  /* Useless if `global.useOracle is != 0` */
  function setGasprice(uint gasprice) public {
    authOnly();
    /* Checking the size of `gasprice` is necessary to prevent a) data loss when `gasprice` is copied to an `OfferDetail` struct, and b) overflow when `gasprice` is used in calculations. */
    require(uint16(gasprice) == gasprice, "mgv/config/gasprice/16bits");
    //+clear+

    global = $$(set_global("global", [["gasprice", "gasprice"]]));
    emit MgvEvents.SetGasprice(gasprice);
  }

  /* ### `gasmax` */
  function setGasmax(uint gasmax) public {
    authOnly();
    /* Since any new `gasreq` is bounded above by `config.gasmax`, this check implies that all offers' `gasreq` is 24 bits wide at most. */
    require(uint24(gasmax) == gasmax, "mgv/config/gasmax/24bits");
    //+clear+
    global = $$(set_global("global", [["gasmax", "gasmax"]]));
    emit MgvEvents.SetGasmax(gasmax);
  }

  /* ### `governance` */
  /* Since this is called from the constructor before gov has been set, the setter must be split between an internal and an external function. */
  function setGovernance(address governanceAddress) external {
    authOnly();
    _setGovernance(governanceAddress);
  }

  function _setGovernance(address governanceAddress) internal {
    governance = governanceAddress;
    emit MgvEvents.SetGovernance(governanceAddress);
  }

  function setVault(address vaultAddress) public {
    authOnly();
    vault = vaultAddress;
    emit MgvEvents.SetVault(vaultAddress);
  }

  function setMonitor(address monitor) public {
    authOnly();
    global = $$(set_global("global", [["monitor", "monitor"]]));
    emit MgvEvents.SetMonitor(monitor);
  }

  function authOnly() internal view {
    require(
      msg.sender == governance || msg.sender == address(this),
      "mgv/unauthorized"
    );
  }

  function setUseOracle(bool useOracle) public {
    authOnly();
    uint _useOracle = useOracle ? 1 : 0;
    global = $$(set_global("global", [["useOracle", "_useOracle"]]));
    emit MgvEvents.SetUseOracle(useOracle);
  }

  function setNotify(bool notify) public {
    authOnly();
    uint _notify = notify ? 1 : 0;
    global = $$(set_global("global", [["notify", "_notify"]]));
    emit MgvEvents.SetNotify(notify);
  }
}
