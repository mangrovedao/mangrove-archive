pragma solidity ^0.7.0;
pragma abicoder v2;
import "./CompoundLender.sol";
import "hardhat/console.sol";

// SPDX-License-Identifier: MIT

abstract contract CompoundTrader is CompoundLender {
  event ErrorOnBorrow(address cToken, uint amount, uint errorCode);
  event ErrorOnRepay(address cToken, uint amount, uint errorCode);

  ///@notice method to get `base` during makerExecute
  ///@param base address of the ERC20 managing `base` token
  ///@param amount of token that the trade is still requiring
  function __get__(IERC20 base, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    if (!isPooled(address(base))) {
      return amount;
    }
    IcERC20 base_cErc20 = IcERC20(overlyings[base]); // this is 0x0 if base is not compound sourced for borrow.

    if (address(base_cErc20) == address(0)) {
      return amount;
    }

    // 1. Computing total borrow and redeem capacities of underlying asset
    (uint redeemable, uint liquidity_after_redeem) = maxGettableUnderlying(
      address(base_cErc20)
    );

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
    uint toBorrow = min(liquidity_after_redeem, amount);
    if (toBorrow == 0) {
      return amount;
    }
    // 3. trying to borrow missing liquidity
    uint errorCode = base_cErc20.borrow(toBorrow);
    if (errorCode != 0) {
      emit ErrorOnBorrow(address(base_cErc20), toBorrow, errorCode);
      return amount; // unable to borrow requested amount
    }
    // if ETH were borrowed, one needs to turn them into wETH
    if (isCeth(base_cErc20)) {
      weth.deposit{value: toBorrow}();
    }
    return sub_(amount, toBorrow);
  }

  /// @notice user need to have approved `quote` overlying in order to repay borrow
  function __put__(IERC20 quote, uint amount) internal virtual override {
    //optim
    if (amount == 0 || !isPooled(address(quote))) {
      return;
    }
    // NB: overlyings[wETH] = cETH
    IcERC20 cQuote = IcERC20(overlyings[quote]);
    if (address(cQuote) == address(0)) {
      return;
    }
    // trying to repay debt if user is in borrow position for quote token
    uint toRepay = min(cQuote.borrowBalanceCurrent(address(this)), amount); //accrues interests

    uint errCode;
    if (isCeth(cQuote)) {
      // turning WETHs to ETHs
      weth.withdraw(toRepay);
      // OK since repayBorrow throws if failing in the case of Eth
      cQuote.repayBorrow{value: toRepay}();
    } else {
      errCode = cQuote.repayBorrow(toRepay);
    }
    uint toMint;
    if (errCode != 0) {
      emit ErrorOnRepay(address(cQuote), toRepay, errCode);
      toMint = amount;
    } else {
      toMint = amount - toRepay;
    }

    compoundMint(cQuote, toMint);
  }
}
