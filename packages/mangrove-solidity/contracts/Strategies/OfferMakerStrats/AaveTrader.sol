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

  ///@notice method to get `outbound_tkn` during makerExecute
  ///@param outbound_tkn address of the ERC20 managing `outbound_tkn` token
  ///@param amount of token that the trade is still requiring
  function __get__(IERC20 outbound_tkn, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    // 1. Computing total borrow and redeem capacities of underlying asset
    (uint redeemable, uint liquidity_after_redeem) = maxGettableUnderlying(
      outbound_tkn
    );

    // 2. trying to redeem liquidity from Compound
    uint toRedeem = min(redeemable, amount);

    uint notRedeemed = aaveRedeem(outbound_tkn, toRedeem);
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
    try
      lendingPool.borrow(
        address(outbound_tkn),
        toBorrow,
        interestRateMode,
        referralCode,
        address(this)
      )
    {
      return sub_(amount, toBorrow);
    } catch Error(string memory errorCode) {
      emit ErrorOnBorrow(address(outbound_tkn), toBorrow, errorCode);
      return amount; // unable to borrow requested amount
    } catch {
      emit ErrorOnBorrow(address(outbound_tkn), toBorrow, "Unexpected reason");
      return amount;
    }
  }

  /// @notice user need to have approved `inbound_tkn` overlying in order to repay borrow
  function __put__(IERC20 inbound_tkn, uint amount) internal virtual override {
    //optim
    if (amount == 0) {
      return;
    }
    // trying to repay debt if user is in borrow position for inbound_tkn token
    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
      address(inbound_tkn)
    );

    uint debtOfUnderlying;
    if (interestRateMode == 1) {
      debtOfUnderlying = IERC20(reserveData.stableDebtTokenAddress).balanceOf(
        address(this)
      );
    } else {
      debtOfUnderlying = IERC20(reserveData.variableDebtTokenAddress).balanceOf(
          address(this)
        );
    }

    uint toRepay = min(debtOfUnderlying, amount);

    uint toMint;
    try
      lendingPool.repay(
        address(inbound_tkn),
        toRepay,
        interestRateMode,
        address(this)
      )
    {
      toMint = sub_(amount, toRepay);
    } catch {
      emit ErrorOnRepay(address(inbound_tkn), toRepay);
      toMint = amount;
    }
    aaveMint(inbound_tkn, toMint);
  }
}
