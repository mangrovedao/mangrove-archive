pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

abstract contract LiquidityAmplifier is MangroveOffer {

  struct LiquidityAmplifier_env {IERC20 pool;}

  LiquidityAmplifier_env liquidityAmplifier_env;

  constructor(address payable mgv, address base_erc, address _pool)
    MangroveOffer(mgv, base_erc){
      liquidityAmplifier_env = LiquidityAmplifier_env({pool: IERC20(_pool)});
    }

  function setLiquiditySource(address new_pool) external onlyCaller(admin) {
    liquidityAmplifier_env.pool = IERC20(new_pool);
    log("Pool",new_pool);
  }

  function __trade_checkLiquidity(MgvC.SingleOrder calldata order) internal returns (TradeResult, bytes32){
    uint pool_balance = liquidityAmplifier_env.pool.balanceOf(address(this));
    if (order.wants <= pool_balance) {
      return (TradeResult.Proceed, bytes32(pool_balance-order.wants));
    }
    else {
      return (TradeResult.Drop, bytes32(order.wants - pool_balance)) ;
    }
  }

}
