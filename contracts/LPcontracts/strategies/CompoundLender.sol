pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../interfaces/ICompound.sol";

// SPDX-License-Identifier: MIT

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

  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with compound
  /**************************************************************************/

  ///@notice approval of cToken contract by the underlying is necessary for minting and repaying borrow
  ///@notice user must use this function to do so.
  function approveCToken(
    address token,
    address cToken,
    uint amount
  ) external onlyAdmin {
    IERC20(token).approve(cToken, amount);
  }

  ///@notice enters markets in order to be able to use assets as collateral
  function enterMarkets(address[] calldata cTokens)
    external
    onlyAdmin
    returns (uint[] memory)
  {
    return comptroller.enterMarkets(cTokens);
  }

  ///@notice exits markets
  function exitMarkets(address cToken) external onlyAdmin returns (uint) {
    return comptroller.exitMarket(cToken);
  }

  ///@notice claims COMP token for `this` contract. One may afterward transfer them using `MangroveOffer.transferToken`
  function claimComp() external onlyAdmin {
    comptroller.claimComp(address(this));
  }

  ///@notice To declare put/get methods should use Compound to manage token assets
  ///@param token address of the underlying token
  ///@param cToken address of the overlying token. Put 0x0 here to stop getting/putting token on Compound
  function setCompoundSource(address token, address cToken) external onlyAdmin {
    overlyings[token] = cToken;
  }

  function setCompoundPutFlag(address erc20, bool flag) external onlyAdmin {
    compoundPutFlag[erc20] = flag;
  }

  function setCompoundGetFlag(address erc20, bool flag) external onlyAdmin {
    compoundGetFlag[erc20] = flag;
  }

  /// @notice struct to circumvent stack too deep error in `maxGettableUnderlying` function
  struct Heap {
    uint cTokenBalance;
    uint exchangeRateMantissa;
    uint liquidity;
    uint collateralFactorMantissa;
    uint maxRedeemable;
    uint balanceOfUnderlying;
    uint priceMantissa;
    uint underlyingLiquidity;
    MathError mErr;
    uint errCode;
  }

  function heapError(Heap memory heap) private pure returns (bool) {
    return (heap.errCode != 0 || heap.mErr != MathError.NO_ERROR);
  }

  /// @notice Computes maximal borrow capacity of the account and maximal redeem capacity
  /// @notice The returned value is underestimated unless accrueInterest is called in the transaction
  /// @notice Putting liquidity on Compound (either through minting or borrowing) will accrue interests
  /// return (underlyingLiquidity, maxRedeemableUnderlying)
  function maxGettableUnderlying(IcERC20 cToken)
    internal
    view
    returns (uint, uint)
  {
    Heap memory heap;
    // NB balance below is underestimated unless accrue interest was triggered earlier in the transaction
    (heap.errCode, heap.cTokenBalance, , heap.exchangeRateMantissa) = cToken
      .getAccountSnapshot(msg.sender); // underapprox
    heap.priceMantissa = oracle.getUnderlyingPrice(cToken);
    // balanceOfUnderlying(A) : cA.balance * exchange_rate(cA,A)
    (heap.mErr, heap.balanceOfUnderlying) = mulScalarTruncate(
      Exp({mantissa: heap.exchangeRateMantissa}),
      heap.cTokenBalance
    );
    if (heapError(heap)) {
      return (0, 0);
    }

    // max amount of Base token than can be borrowed
    (
      heap.errCode,
      heap.liquidity, // is USD:18 decimals
      /*shortFall*/
    ) = comptroller.getAccountLiquidity(msg.sender); // underapprox
    // to get liquidity expressed in base token instead of USD
    (heap.mErr, heap.underlyingLiquidity) = divScalarByExpTruncate(
      heap.liquidity,
      Exp({mantissa: heap.priceMantissa})
    );
    if (heapError(heap)) {
      return (0, 0);
    }
    (, heap.collateralFactorMantissa, ) = comptroller.markets(address(cToken));
    // if collateral factor is 0 then any token can be redeemed from the pool
    // also true if market is not entered
    if (heap.collateralFactorMantissa == 0 || !comptroller.checkMembership(msg.sender, cToken)) {
      return (heap.underlyingLiquidity, heap.balanceOfUnderlying);
    }

    // maxRedeem:[underlying] = liquidity:[USD / 18 decimals ] / (price(Base):[USD.underlying^-1 / 18 decimals] * collateralFactor(Base): [0-1] 18 decimals)
    (heap.mErr, heap.maxRedeemable) = divScalarByExpTruncate(
      heap.liquidity,
      mul_(
        Exp({mantissa: heap.collateralFactorMantissa}),
        Exp({mantissa: heap.priceMantissa})
      )
    );
    if (heapError(heap)) {
      return (0, 0);
    }
    return (heap.underlyingLiquidity, min(heap.maxRedeemable, heap.balanceOfUnderlying));
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
    IcERC20 base_cErc20 = IcERC20(overlyings[base]); // this is 0x0 if base is not compound sourced.
    if (address(base_cErc20) == address(0)) {
      return amount;
    }
    (,uint redeemable) = maxGettableUnderlying(base_cErc20);
    uint redeemAmount = min(redeemable, amount);
    if (compoundRedeem(base_cErc20, redeemAmount) == 0) {
      // redeemAmount was transfered to `this`
      return (amount - redeemAmount);
    }
    return amount;
  }

  function compoundRedeem(IcERC20 cBase, uint amountToRedeem)
    internal
    returns (uint)
  {
    uint errorCode = cBase.redeemUnderlying(amountToRedeem); // accrues interests
    if (errorCode == 0) {
      //compound redeem was a success
      return 0;
    } else {
      //compound redeem failed
      emit ErrorOnRedeem(address(cBase), amountToRedeem, errorCode);
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
    IcERC20 cToken = IcERC20(overlyings[quote]);
    if (address(cToken) != address(0)) {
      return compoundMint(cToken, amount);
    } else {
      return amount;
    }
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  // NB `cToken` contract MUST be approved to perform `transferFrom token` by `this` contract.
  /// @notice user need to approve cToken in order to mint
  function compoundMint(
    IcERC20 cToken,
    uint amount
  ) internal returns (uint missing) {
    // Approve transfer on the ERC20 contract (not needed if cERC20 is already approved for `this`)
    // IERC20(cToken.underlying()).approve(cToken, amount);
    uint errCode = cToken.mint(amount); // accrues interest
    // Mint cTokens
    if (errCode == 0) {
      return 0;
    } else {
      emit ErrorOnMint(address(cToken), amount, errCode);
      return amount;
    }
  }
}
