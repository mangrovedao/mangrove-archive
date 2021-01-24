// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import {DexCommon as DC} from "./DexCommon.sol";

interface IMaker {
  struct Trade {
    address base;
    address quote;
    uint takerWants;
    uint takerGives;
    address taker;
    uint offerGasprice;
    uint offerGasreq;
    uint offerId;
    uint offerWants;
    uint offerGives;
    bool offerWillDelete;
  }

  // Maker sends quote to taker
  // In normal dex, they already received base
  // In inverted dex, they did not
  //function makerTrade(Trade calldata trade) external returns (bytes32);

  // Maker sends quote to taker
  // In normal dex, they already received base
  // In inverted dex, they did not
  function makerTrade(
    DC.SingleOrder calldata sor,
    address taker,
    bool willDelete
  ) external returns (bytes32);

  struct Posthook {
    address base;
    address quote;
    uint takerWants;
    uint takerGives;
    uint offerId;
    bool offerDeleted;
    bool success;
  }

  // Maker callback after trade
  function makerPosthook(Posthook calldata posthook) external;

  event Execute(
    address dex,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );
}

interface ITaker {
  // Inverted dex only: taker acquires enough base to pay back quote loan
  function takerTrade(
    address base,
    address quote,
    uint totalGot,
    uint totalGives
  ) external;
}

/* Governance contract interface */
interface IGovernance {
  function recordTrade(
    address base,
    address quote,
    uint takerWants,
    uint takerGives,
    address taker,
    address maker,
    bool success,
    uint gasused,
    uint gasbase,
    uint gasreq,
    uint gasprice
  ) external;
}

// IERC20 From OpenZeppelin code

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
  /**
   * @dev Returns the amount of tokens in existence.
   */
  function totalSupply() external view returns (uint);

  /**
   * @dev Returns the amount of tokens owned by `account`.
   */
  function balanceOf(address account) external view returns (uint);

  /**
   * @dev Moves `amount` tokens from the caller's account to `recipient`.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transfer(address recipient, uint amount) external returns (bool);

  /**
   * @dev Returns the remaining number of tokens that `spender` will be
   * allowed to spend on behalf of `owner` through {transferFrom}. This is
   * zero by default.
   *
   * This value changes when {approve} or {transferFrom} are called.
   */
  function allowance(address owner, address spender)
    external
    view
    returns (uint);

  /**
   * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * IMPORTANT: Beware that changing an allowance with this method brings the risk
   * that someone may use both the old and the new allowance by unfortunate
   * transaction ordering. One possible solution to mitigate this race
   * condition is to first reduce the spender's allowance to 0 and set the
   * desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   *
   * Emits an {Approval} event.
   */
  function approve(address spender, uint amount) external returns (bool);

  /**
   * @dev Moves `amount` tokens from `sender` to `recipient` using the
   * allowance mechanism. `amount` is then deducted from the caller's
   * allowance.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transferFrom(
    address sender,
    address recipient,
    uint amount
  ) external returns (bool);

  /**
   * @dev Emitted when `value` tokens are moved from one account (`from`) to
   * another (`to`).
   *
   * Note that `value` may be zero.
   */
  event Transfer(address indexed from, address indexed to, uint value);

  /**
   * @dev Emitted when the allowance of a `spender` for an `owner` is set by
   * a call to {approve}. `value` is the new allowance.
   */
  event Approval(address indexed owner, address indexed spender, uint value);
}
