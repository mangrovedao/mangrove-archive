pragma solidity ^0.7.0;
import "../../interfaces.sol";

interface ICompoundPriceOracle {
  function getUnderlyingPrice(IcERC20 cToken) external view returns (uint);
}

interface IComptroller {
  // from https://github.com/compound-finance/compound-protocol
  
  struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;

        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;

        /// @notice Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;

        /// @notice Whether or not this market receives COMP
        bool isComped;
    }
  // adding usefull public getters
  function oracle() external returns (ICompoundPriceOracle oracle);
  function markets(address cToken) returns (Market market);

  /*** Assets You Are In ***/

  function enterMarkets(address[] calldata cTokens)
    external
    returns (uint[] memory);

  function exitMarket(address cToken) external returns (uint);

}

interface IcERC20 is IERC20 {
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
  function mint(uint mintAmount) external returns (uint);
  function redeem(uint redeemTokens) external returns (uint);
  function redeemUnderlying(uint redeemAmount) external returns (uint);
  function borrow(uint borrowAmount) external returns (uint);
  function repayBorrow(uint repayAmount) external returns (uint);
  function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
  function liquidateBorrow(address borrower, uint repayAmount, CTokenInterface cTokenCollateral) external returns (uint);
  function sweepToken(EIP20NonStandardInterface token) external;
  
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
