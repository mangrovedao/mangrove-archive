pragma solidity ^0.7.0;
pragma abicoder v2;
import "./CompoundLender.sol";

contract CompoundTrader is CompoundLender {
  constructor(address _comptroller, address payable _MGV)
    CompoundLender(_comptroller, _MGV)
  {}

  event ErrorOnBorrow(address cToken, uint amount, uint errorCode);
  event ErrorOnRepay(address cToken, uint amount, uint errorCode);

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
      return amount;
    }
    address base_cErc20 = overlyings[base]; // this is 0x0 if base is not compound sourced for borrow.

    if (base_cErc20 == address(0)) {
      return amount;
    }

    // 1. Computing total borrow and redeem capacities
    (uint gettable, uint redeemable) =
      maxGettableUnderlying(IcERC20(base_cErc20));

    // 2. trying to redeem liquidity from Compound
    uint toRedeem = redeemable > amount ? amount : redeemable;
    uint notRedeemed = compoundRedeem(base, toRedeem);
    if (notRedeemed > 0 && toRedeem > 0) {
      // => notRedeemed == toRedeem
      // this should happen unless compound is out of cash, thus no need to try to borrow
      // log already emitted by `compoundRedeem`
      return amount;
    }
    // borrowable = gettable - toRedeem
    uint toBorrow = sub_(gettable, toRedeem);

    // 3. trying to borrow missing liquidity
    uint errorCode = IcERC20(base_cErc20).borrow(toBorrow);
    if (errorCode != 0) {
      emit ErrorOnBorrow(base_cErc20, toBorrow, errorCode);
      return sub_(amount, toRedeem); // unable to borrow requested amount
    }
    return sub_(amount, add_(toRedeem, toBorrow));
  }

  /// @notice user need to have approved `quote` overlying in order to repay borrow
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
    IcERC20 cQuote = IcERC20(overlyings[quote]);
    if (address(cQuote) == address(0)) {
      return amount;
    }

    uint repayable = cQuote.borrowBalanceCurrent(msg.sender);
    uint toRepay = repayable > amount ? amount : repayable;
    uint toMint;
    uint errCode = cQuote.repayBorrow(toRepay);
    if (errCode != 0) {
      emit ErrorOnRepay(address(cQuote), toRepay, errCode);
      toMint = amount;
    } else {
      toMint = amount - toRepay;
    }
    return compoundMint(quote, address(cQuote), toMint);
  }
}
