pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "./CompoundInterface.sol";

contract CompoundLender is MangroveOffer, Exponential {
  event ErrorOnRedeem(address cToken, uint amount, uint errorCode);
  event ErrorOnMint(address cToken, uint amount, uint errorCode);
  event ComptrollerError(address comp, uint errorCode);

  // mapping : ERC20 -> cERC20
  mapping(address => address) public overlyings;
  mapping(address => bool) public compoundPutFlag;
  mapping(address => bool) public compoundGetFlag;

  // address of the comptroller
  IComptroller public immutable comptroller;

  // address of the price oracle used by the comptroller
  ICompoundPriceOracle public immutable oracle;

  constructor(address _comptroller, address payable _MGV) MangroveOffer(_MGV) {
    comptroller = IComptroller(_comptroller); // comptroller address
    oracle = IComptroller(_comptroller).oracle(); // pricefeed used by the comptroller
  }

  ///@notice approval of cToken contract by the underlying is necessary for minting and repaying borrow
  ///@notice user must use this function to do so.
  function approveCToken(
    IERC20 token,
    IcERC20 cToken,
    uint amount
  ) external onlyCaller(admin) {
    token.approve(address(cToken), amount);
  }

  ///@notice To declare put/get methods should use Compound to manage token assets
  ///@param token address of the underlying token
  ///@param cToken address of the overlying token. Put 0x0 here to stop getting/putting token on Compound
  function setCompoundSource(address token, address cToken)
    external
    onlyCaller(admin)
  {
    overlyings[token] = cToken;
  }

  function setCompoundPutFlag(address erc20, bool flag)
    external
    onlyCaller(admin)
  {
    compoundPutFlag[erc20] = flag;
  }

  function setCompoundGetFlag(address erc20, bool flag)
    external
    onlyCaller(admin)
  {
    compoundGetFlag[erc20] = flag;
  }

  /// @notice Returns maximal borrow capacity of the account and maximal redeem capacity
  /// @notice accrues interests of compound
  function maxGettableUnderlying(IcERC20 cToken)
    internal
    view
    returns (uint, uint)
  {
    // gets account liquidity in USD units
    (uint errCode, uint liquidity, ) =
      comptroller.getAccountLiquidity(msg.sender);
    if (errCode != 0) {
      return (0, 0);
    }
    // maxRedeem = liquidity / (CF_underlying * price_underlying)
    (, uint collateralFactorMantissa, ) = comptroller.markets(address(cToken));
    (, uint maxRedeemableUnderlying) =
      divScalarByExpTruncate(
        liquidity,
        mul_(
          Exp({mantissa: collateralFactorMantissa}),
          Exp({mantissa: oracle.getUnderlyingPrice(cToken)})
        )
      );
    return (liquidity, maxRedeemableUnderlying);
  }

  ///@notice method to get `base` during makerTrade
  ///@param base address of the ERC20 managing `base` token
  ///@param amount of token that the trade is still requiring
  function __get__(address base, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    if (!compoundGetFlag[base]) {
      // if flag says not to fetch liquidity on compound
      return amount;
    }
    address base_cErc20 = overlyings[base]; // this is 0x0 if base is not compound sourced.
    if (base_cErc20 == address(0)) {
      return amount;
    }
    (, uint redeemable) = maxGettableUnderlying(IcERC20(base_cErc20));
    uint redeemAmount = redeemable > amount ? amount : redeemable;
    return compoundRedeem(base_cErc20, redeemAmount);
  }

  function compoundRedeem(address cBase, uint amountToRedeem)
    internal
    returns (uint)
  {
    uint errorCode = IcERC20(cBase).redeemUnderlying(amountToRedeem);
    if (errorCode == 0) {
      //compound redeem was a success
      return 0;
    } else {
      //ompound redeem failed
      emit ErrorOnRedeem(cBase, amountToRedeem, errorCode);
      return amountToRedeem;
    }
  }

  function __put__(address quote, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    //optim
    if (amount == 0) {
      return 0;
    }
    if (!compoundPutFlag[quote]) {
      return amount;
    }
    address cToken = overlyings[quote];
    if (cToken != address(0)) {
      return compoundMint(quote, cToken, amount);
    } else {
      return amount;
    }
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  // NB `cToken` contract MUST be approved to perform `transferFrom token` by `this` contract.
  /// @notice user need to approve cToken in order to mint
  function compoundMint(
    address token,
    address cToken,
    uint amount
  ) internal returns (uint missing) {
    // Approve transfer on the ERC20 contract (not needed if cERC20 is already approved for `this`)
    // IERC20(token).approve(cToken, amount);
    uint errCode = IcERC20(cToken).mint(amount);
    // Mint cTokens
    if (errCode == 0) {
      return 0;
    } else {
      emit ErrorOnMint(cToken, amount, errCode);
      return amount;
    }
  }
}
