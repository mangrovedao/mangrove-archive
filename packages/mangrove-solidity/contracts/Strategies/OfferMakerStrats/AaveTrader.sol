pragma solidity ^0.7.0;
pragma abicoder v2;
import "./AaveLender.sol";
import "hardhat/console.sol";

// SPDX-License-Identifier: MIT

abstract contract AaveTrader is AaveLender {
  uint public immutable interestRateMode;

  constructor(uint _interestRateMode) {
    interestRateMode = _interestRateMode;
  }

  event ErrorOnBorrow(address cToken, uint amount, string errorCode);
  event ErrorOnRepay(address cToken, uint amount);

  ///@notice method to get `base` during makerExecute
  ///@param base address of the ERC20 managing `base` token
  ///@param amount of token that the trade is still requiring
  function __get__(IERC20 base, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    // 1. Computing total borrow and redeem capacities of underlying asset
    (uint redeemable, uint liquidity_after_redeem) =
      maxGettableUnderlying(base);

    // 2. trying to redeem liquidity from Compound
    uint toRedeem = min(redeemable, amount);

    uint notRedeemed = aaveRedeem(base, toRedeem);
    if (notRedeemed > 0 && toRedeem > 0) {
      // => notRedeemed == toRedeem
      // this should not happen unless compound is out of cash, thus no need to try to borrow
      // log already emitted by `compoundRedeem`
      return amount;
    }
    amount = sub_(amount, toRedeem);
    uint toBorrow= min(liquidity_after_redeem, amount); 
    if (toBorrow == 0) {
      return amount;
    }

    // 3. trying to borrow missing liquidity
    try lendingPool.borrow(address(base), toBorrow, interestRateMode, referralCode, address(this)) {
      return sub_(amount, toBorrow);
    } catch Error(string memory errorCode){
      emit ErrorOnBorrow(address(base), toBorrow, errorCode);
      return amount; // unable to borrow requested amount
    }
  }

  /// @notice user need to have approved `quote` overlying in order to repay borrow
  function __put__(IERC20 quote, uint amount) internal virtual override {
    //optim
    if (amount == 0) {
      return;
    }
    // trying to repay debt if user is in borrow position for quote token
    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(address(quote));

    uint debtOfUnderlying;
    if (interestRateMode == 1) {
      debtOfUnderlying = IERC20(reserveData.stableDebtTokenAddress).balanceOf(address(this));
    }
    else {
      debtOfUnderlying = IERC20(reserveData.variableDebtTokenAddress).balanceOf(address(this));
    }

    uint toRepay = min(debtOfUnderlying, amount);
    
    uint toMint;
    try lendingPool.repay(address(quote), toRepay, interestRateMode, address(this)) {
      toMint = sub_(amount, toRepay) ;
    } catch {
      emit ErrorOnRepay(address(quote), toRepay);
      toMint = amount;
    }
    aaveMint(quote, toMint);
  }
}
