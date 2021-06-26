pragma solidity ^0.7.0;
pragma abicoder v2;
import "./CompoundLender.sol";

// SPDX-License-Identifier: MIT

contract CompoundTrader is CompoundLender {
  constructor(address _comptroller, address payable _MGV)
    CompoundLender(_comptroller, _MGV)
  {}

  event ErrorOnBorrow(address cToken, uint amount, uint errorCode);
  event ErrorOnRepay(address cToken, uint amount, uint errorCode);

  ///@notice method to get `base` during makerExecute
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
    IcERC20 base_cErc20 = IcERC20(overlyings[base]); // this is 0x0 if base is not compound sourced for borrow.

    if (address(base_cErc20) == address(0)) {
      return amount;
    }

    // 1. Computing total borrow and redeem capacities of underlying asset
    (uint liquidity, uint redeemable) = maxGettableUnderlying(base_cErc20);

    // 2. trying to redeem liquidity from Compound
    uint toRedeem = min(redeemable, amount);
    uint notRedeemed = compoundRedeem(base_cErc20, toRedeem);
    if (notRedeemed > 0 && toRedeem > 0) {
      // => notRedeemed == toRedeem
      // this should not happen unless compound is out of cash, thus no need to try to borrow
      // log already emitted by `compoundRedeem`
      return amount;
    }
    amount = sub_(amount, toRedeem);
    uint toBorrow;
    if (comptroller.checkMembership(msg.sender, base_cErc20)) {
      //base_cErc20 participates to liquidity
      toBorrow = min(sub_(liquidity, toRedeem), amount); // we know liquidity > toRedeem
    } else {
      toBorrow = min(liquidity, amount); // redeemed token do not decrease liquidity
    }
    if (toBorrow == 0) {
      return amount;
    }

    // 3. trying to borrow missing liquidity
    uint errorCode = base_cErc20.borrow(toBorrow);
    if (errorCode != 0) {
      emit ErrorOnBorrow(address(base_cErc20), toBorrow, errorCode);
      return amount; // unable to borrow requested amount
    }
    return sub_(amount, toBorrow);
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

    uint toRepay = min(cQuote.borrowBalanceCurrent(msg.sender), amount); //accrues interests
    uint toMint;
    uint errCode = cQuote.repayBorrow(toRepay);
    if (errCode != 0) {
      emit ErrorOnRepay(address(cQuote), toRepay, errCode);
      toMint = amount;
    } else {
      toMint = amount - toRepay;
    }
    return compoundMint(cQuote, toMint);
  }
}
