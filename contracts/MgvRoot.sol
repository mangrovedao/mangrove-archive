// SPDX-License-Identifier:	AGPL-3.0

// MgvRoot.sol

// Copyright (C) 2021 Giry SAS.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

/* `MgvRoot` and its descendants describe an orderbook-based exchange ("the Mangrove") where market makers *do not have to provision their offer*. See `structs.js` for a longer introduction. In a nutshell: each offer created by a maker specifies an address (`maker`) to call upon offer execution by a taker. In the normal mode of operation, the Mangrove transfers the amount to be paid by the taker to the maker, calls the maker, attempts to transfer the amount promised by the maker to the taker, and reverts if it cannot.

   There is one Mangrove contract that manages all tradeable pairs. This reduces deployment costs for new pairs and lets market makers have all their provision for all pairs in the same place.

   The interaction map between the different actors is as follows:
   <img src="./contactMap.png" width="190%"></img>

   The sequence diagram of a market order is as follows:
   <img src="./sequenceChart.png" width="190%"></img>

   There is a secondary mode of operation in which the _maker_ flashloans the sold amount to the taker.

   The Mangrove contract is `abstract` and accomodates both modes. Two contracts, `Mangrove` and `InvertedMangrove` inherit from it, one per mode of operation.

   The contract structure is as follows:
   <img src="./modular_mangrove.svg" width="180%"> </img>
 */

pragma solidity ^0.7.0;
pragma abicoder v2;
import {MgvLib as ML, MgvEvents, IMgvMonitor} from "./MgvLib.sol";

/* `MgvRoot` contains state variables used everywhere in the operation of the Mangrove and their related function. */
contract MgvRoot {
  /* # State variables */
  //+clear+
  /* The `vault` address. If a pair has fees >0, those fees are sent to the vault. */
  address public vault;

  /* Global mgv configuration, encoded in a 256 bits word. The information encoded is detailed in [`structs.js`](#structs.js). */
  bytes32 public global;
  /* Configuration mapping for each token pair of the form `base => quote => bytes32`. The structure of each `bytes32` value is detailed in [`structs.js`](#structs.js). */
  mapping(address => mapping(address => bytes32)) public locals;

  /* # Configuration Reads */

  /* Reading the configuration for a pair involves reading the config global to all pairs and the local one. In addition, a global parameter (`gasprice`) and a local one (`density`) may be read from the oracle. */
  function config(address base, address quote)
    public view
    returns (bytes32 _global, bytes32 _local)
  {
    _global = global;
    _local = locals[base][quote];
    if ($$(global_useOracle("_global")) > 0) {
      (uint gasprice, uint density) = IMgvMonitor($$(global_monitor("_global")))
        .read(base, quote);
      _global = $$(set_global("_global", [["gasprice", "gasprice"]]));
      _local = $$(set_local("_local", [["density", "density"]]));
    }
  }

  /* Returns the configuration in an ABI-compatible struct. Should not be called internally, would be a huge memory copying waste. Use `config` instead. */
  function getConfig(address base, address quote)
    external view
    returns (ML.Config memory ret)
  {
    (bytes32 _global, bytes32 _local) = config(base, quote);
    ret.global = ML.Global({
      monitor: $$(global_monitor("_global")),
      useOracle: $$(global_useOracle("_global")) > 0,
      notify: $$(global_notify("_global")) > 0,
      gasprice: $$(global_gasprice("_global")),
      gasmax: $$(global_gasmax("_global")),
      dead: $$(global_dead("_global")) > 0
    });
    ret.local = ML.Local({
      active: $$(local_active("_local")) > 0,
      overhead_gasbase: $$(local_overhead_gasbase("_local")),
      offer_gasbase: $$(local_offer_gasbase("_local")),
      fee: $$(local_fee("_local")),
      density: $$(local_density("_local")),
      best: $$(local_best("_local")),
      lock: $$(local_lock("_local")) > 0,
      last: $$(local_last("_local"))
    });
  }

  /* Convenience function to check whether given pair is locked */
  function locked(address base, address quote) external view returns (bool) {
    bytes32 local = locals[base][quote];
    return $$(local_lock("local")) > 0;
  }

  /*
  # Gatekeeping

  Gatekeeping functions are safety checks called in various places.
  */

  /* `unlockedMarketOnly` protects modifying the market while an order is in progress. Since external contracts are called during orders, allowing reentrancy would, for instance, let a market maker replace offers currently on the book with worse ones. Note that the external contracts _will_ be called again after the order is complete, this time without any lock on the market.  */
  function unlockedMarketOnly(bytes32 local) internal pure {
    require($$(local_lock("local")) == 0, "mgv/reentrancyLocked");
  }

  /* <a id="Mangrove/definition/liveMgvOnly"></a>
     In case of emergency, the Mangrove can be `kill`ed. It cannot be resurrected. When a Mangrove is dead, the following operations are disabled :
       * Executing an offer
       * Sending ETH to the Mangrove the normal way. Usual [shenanigans](https://medium.com/@alexsherbuck/two-ways-to-force-ether-into-a-contract-1543c1311c56) are possible.
       * Creating a new offer
   */
  function liveMgvOnly(bytes32 _global) internal pure {
    require($$(global_dead("_global")) == 0, "mgv/dead");
  }

  /* When the Mangrove is deployed, all pairs are inactive by default (since `locals[base][quote]` is 0 by default). Offers on inactive pairs cannot be taken or created. They can be updated and retracted. */
  function activeMarketOnly(bytes32 _global, bytes32 _local) internal pure {
    liveMgvOnly(_global);
    require($$(local_active("_local")) > 0, "mgv/inactive");
  }
}
