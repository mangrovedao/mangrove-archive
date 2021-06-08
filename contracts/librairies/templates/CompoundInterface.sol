pragma solidity ^0.7.0;
import "../../interfaces.sol";

interface ICompoundPriceOracle {
  function getUnderlyingPrice(IcERC20 cToken) external view returns (uint);
}

interface IComptroller {
  function oracle() external returns (ICompoundPriceOracle oracle);

  /*** Assets You Are In ***/

  function enterMarkets(address[] calldata cTokens)
    external
    returns (uint[] memory);

  function exitMarket(address cToken) external returns (uint);

  /*** Policy Hooks ***/

  function mintAllowed(
    address cToken,
    address minter,
    uint mintAmount
  ) external returns (uint);

  function mintVerify(
    address cToken,
    address minter,
    uint mintAmount,
    uint mintTokens
  ) external;

  function redeemAllowed(
    address cToken,
    address redeemer,
    uint redeemTokens
  ) external returns (uint);

  function redeemVerify(
    address cToken,
    address redeemer,
    uint redeemAmount,
    uint redeemTokens
  ) external;

  function borrowAllowed(
    address cToken,
    address borrower,
    uint borrowAmount
  ) external returns (uint);

  function borrowVerify(
    address cToken,
    address borrower,
    uint borrowAmount
  ) external;

  function repayBorrowAllowed(
    address cToken,
    address payer,
    address borrower,
    uint repayAmount
  ) external returns (uint);

  function repayBorrowVerify(
    address cToken,
    address payer,
    address borrower,
    uint repayAmount,
    uint borrowerIndex
  ) external;

  function liquidateBorrowAllowed(
    address cTokenBorrowed,
    address cTokenCollateral,
    address liquidator,
    address borrower,
    uint repayAmount
  ) external returns (uint);

  function liquidateBorrowVerify(
    address cTokenBorrowed,
    address cTokenCollateral,
    address liquidator,
    address borrower,
    uint repayAmount,
    uint seizeTokens
  ) external;

  function seizeAllowed(
    address cTokenCollateral,
    address cTokenBorrowed,
    address liquidator,
    address borrower,
    uint seizeTokens
  ) external returns (uint);

  function seizeVerify(
    address cTokenCollateral,
    address cTokenBorrowed,
    address liquidator,
    address borrower,
    uint seizeTokens
  ) external;

  function transferAllowed(
    address cToken,
    address src,
    address dst,
    uint transferTokens
  ) external returns (uint);

  function transferVerify(
    address cToken,
    address src,
    address dst,
    uint transferTokens
  ) external;

  /*** Liquidity/Liquidation Calculations ***/

  function liquidateCalculateSeizeTokens(
    address cTokenBorrowed,
    address cTokenCollateral,
    uint repayAmount
  ) external view returns (uint, uint);
}

interface IcERC20 is IERC20 {
  /*** User Interface ***/
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
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

  function underlying() external returns (address); // access to public variable containing the address of the underlying ERC20
}
