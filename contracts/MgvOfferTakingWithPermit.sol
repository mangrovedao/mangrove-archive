// SPDX-License-Identifier:	AGPL-3.0

// MgvOfferTakingWithPermit.sol

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

pragma solidity ^0.7.0;
pragma abicoder v2;
import {HasMgvEvents} from "./MgvLib.sol";

import {MgvOfferTaking} from "./MgvOfferTaking.sol";

abstract contract MgvOfferTakingWithPermit is MgvOfferTaking {
  /* Takers may provide allowances on specific pairs, so other addresses can execute orders in their name. Allowance may be set using the usual `approve` function, or through an [EIP712](https://eips.ethereum.org/EIPS/eip-712) `permit`.

  The mapping is `base => quote => owner => spender => allowance` */
  mapping(address => mapping(address => mapping(address => mapping(address => uint))))
    public allowances;
  /* Storing nonces avoids replay attacks. */
  mapping(address => uint) public nonces;
  /* Following [EIP712](https://eips.ethereum.org/EIPS/eip-712), structured data signing has `keccak256("Permit(address base,address quote,address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")` in its prefix. */
  bytes32 public constant PERMIT_TYPEHASH =
    0xb7bf278e51ab1478b10530c0300f911d9ed3562fc93ab5e6593368fe23c077a2;
  /* Initialized in the constructor, `DOMAIN_SEPARATOR` avoids cross-application permit reuse. */
  bytes32 public immutable DOMAIN_SEPARATOR;

  constructor(string memory contractName) {
    /* Initialize [EIP712](https://eips.ethereum.org/EIPS/eip-712) `DOMAIN_SEPARATOR`. */
    uint chainId;
    assembly {
      chainId := chainid()
    }
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        keccak256(
          "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        ),
        keccak256(bytes(contractName)),
        keccak256(bytes("1")),
        chainId,
        address(this)
      )
    );
  }

  /* # Delegation public functions */

  /* Adapted from [Uniswap v2 contract](https://github.com/Uniswap/uniswap-v2-core/blob/55ae25109b7918565867e5c39f1e84b7edd19b2a/contracts/UniswapV2ERC20.sol#L81) */
  function permit(
    address base,
    address quote,
    address owner,
    address spender,
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    require(deadline >= block.timestamp, "mgv/permit/expired");

    uint nonce = nonces[owner]++;
    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        keccak256(
          abi.encode(
            PERMIT_TYPEHASH,
            base,
            quote,
            owner,
            spender,
            value,
            nonce,
            deadline
          )
        )
      )
    );
    address recoveredAddress = ecrecover(digest, v, r, s);
    require(
      recoveredAddress != address(0) && recoveredAddress == owner,
      "mgv/permit/invalidSignature"
    );

    allowances[base][quote][owner][spender] = value;
    emit Approval(base, quote, owner, spender, value);
  }

  function approve(
    address base,
    address quote,
    address spender,
    uint value
  ) external returns (bool) {
    allowances[base][quote][msg.sender][spender] = value;
    emit Approval(base, quote, msg.sender, spender, value);
    return true;
  }

  /* The delegate version of `marketOrder` is `marketOrderFor`, which takes a `taker` address as additional argument. Penalties incurred by failed offers will still be sent to `msg.sender`, but exchanged amounts will be transferred from and to the `taker`. If the `msg.sender`'s allowance for the given `base`,`quote` and `taker` are strictly less than the total amount eventually spent by `taker`, the call will fail. */
  function marketOrderFor(
    address base,
    address quote,
    uint takerWants,
    uint takerGives,
    bool fillWants,
    address taker
  ) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave) = generalMarketOrder(
      base,
      quote,
      takerWants,
      takerGives,
      fillWants,
      taker
    );
    deductSenderAllowance(base, quote, taker, takerGave);
  }

  /* The delegate version of `snipes` is `snipesFor`, which takes a `taker` address as additional argument. */
  function snipesFor(
    address base,
    address quote,
    uint[4][] memory targets,
    bool fillWants,
    address taker
  )
    external
    returns (
      uint successes,
      uint takerGot,
      uint takerGave
    )
  {
    (successes, takerGot, takerGave) = generalSnipes(
      base,
      quote,
      targets,
      fillWants,
      taker
    );
    /* The sender's allowance is verified after the order complete so that the actual amounts are checked against the allowance, instead of the declared `takerGives`. The former may be lower.
    
    An immediate consequence is that any funds availale to Mangrove through `approve` can be used to clean offers. After a `snipesFor` where all offers have failed, all token transfers have been reverted, so `takerGave=0` and the check will succeed -- but the sender will still have received the bounty of the failing offers. */
    deductSenderAllowance(base, quote, taker, takerGave);
  }

  /* # Misc. low-level functions */

  /* Used by `*For` functions, its both checks that `msg.sender` was allowed to use the taker's funds, and decreases the former's allowance. */
  function deductSenderAllowance(
    address base,
    address quote,
    address owner,
    uint amount
  ) internal {
    uint allowed = allowances[base][quote][owner][msg.sender];
    require(allowed >= amount, "mgv/lowAllowance");
    allowances[base][quote][owner][msg.sender] = allowed - amount;
  }
}
