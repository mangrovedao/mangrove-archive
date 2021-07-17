pragma solidity ^0.7.0;
pragma abicoder v2;
// SPDX-License-Identifier: MIT

import "../../MgvLib.sol";

interface ICompoundPriceOracle {
  function getUnderlyingPrice(IcERC20 cToken) external view returns (uint);
}

interface IComptroller {
  // adding usefull public getters
  function oracle() external returns (ICompoundPriceOracle priceFeed);

  function markets(address cToken)
    external
    view
    returns (
      bool isListed,
      uint collateralFactorMantissa,
      bool isComped
    );

  /*** Assets You Are In ***/

  function enterMarkets(address[] calldata cTokens)
    external
    returns (uint[] memory);

  function exitMarket(address cToken) external returns (uint);

  function getAccountLiquidity(address user)
    external
    view
    returns (
      uint errorCode,
      uint liquidity,
      uint shortfall
    );

  function claimComp(address holder) external;

  function checkMembership(address account, IcERC20 cToken)
    external
    view
    returns (bool);
}

interface IcERC20 is IERC20 {
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
  function redeem(uint redeemTokens) external returns (uint);

  function borrow(uint borrowAmount) external returns (uint);

  // for non cETH only
  function repayBorrow(uint repayAmount) external returns (uint);

  // for cETH only
  function repayBorrow() external payable;

  // for non cETH only
  function repayBorrowBehalf(address borrower, uint repayAmount)
    external
    returns (uint);

  // for cETH only
  function repayBorrowBehalf(address borrower) external payable;

  function balanceOfUnderlying(address owner) external returns (uint);

  function getAccountSnapshot(address account)
    external
    view
    returns (
      uint,
      uint,
      uint,
      uint
    );

  function borrowRatePerBlock() external view returns (uint);

  function supplyRatePerBlock() external view returns (uint);

  function totalBorrowsCurrent() external returns (uint);

  function borrowBalanceCurrent(address account) external returns (uint);

  function borrowBalanceStored(address account) external view returns (uint);

  function exchangeRateCurrent() external returns (uint);

  function exchangeRateStored() external view returns (uint);

  function getCash() external view returns (uint);

  function accrueInterest() external returns (uint);

  function seize(
    address liquidator,
    address borrower,
    uint seizeTokens
  ) external returns (uint);

  function redeemUnderlying(uint redeemAmount) external returns (uint);

  function mint(uint mintAmount) external returns (uint);

  // only in cETH
  function mint() external payable;

  // non cETH only
  function underlying() external view returns (address); // access to public variable containing the address of the underlying ERC20

  function isCToken() external view returns (bool); // public constant froim CTokenInterfaces.sol
}
