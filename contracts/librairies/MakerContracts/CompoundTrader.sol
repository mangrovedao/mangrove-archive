pragma solidity ^0.7.0;
pragma abicoder v2;
import "./CompoundLender.sol";

contract CompoundTrader is CompoundLender {
  

  constructor(address _comptroller, address payable _MGV)
  CompoundLender(_comptroller,_MGV){}

  ///@notice method to get `base` during makerTrade
  ///@param base address of the ERC20 managing `base` token
  ///@param amount of token that the trade is still requiring
  function get(address base, uint amount) internal override returns (GetResult, uint) {

    if (!_compoundGet[base]) {return (GetResult.OK, amount);}
    address base_cErc20 = _overlyings[base]; // this is 0x0 if base is not compound sourced for borrow.

    if (base_cErc20 == address(0)) {return (GetResult.Error, amount);}

    // 1. computing available liquidity
    (uint err, uint liquidity, uint) = comptroller.getAccountLiquidity(msg.sender);

    if (err != 0) {return (GetResult.Error, amount);} 
    if (liquidity == 0) {return (GetResult.OK, amount);} 

    // 2. Computing get capacity
    uint gettableUnderlying = divScalarByExpTruncate(
      liquidity,
      Exp({mantissa:oracle.getUnderlyingPrice(IcERC20(base_cErc20))})
    );
    // 3. trying to mint liquidity from Compound
    gettableUnderlying = gettableUnderlying > amount ? amount : gettableUnderlying;
    uint got = super.get(base, gettableUnderlying);
    
    // 4. trying to borrow missing liquidity
    try IcERC20(base_cErc20).borrow(gettableUnderlying - got) returns (uint errorCode) {
      if (errorCode != 0) {
        return (GetResult.Error, amount - got); // unable to borrow requested amount
      }
      return (GetResult.OK, amount - gettableUnderlying);
    } catch {
      (GetResult.FatalError, amount - got); // should revert trade
    }
  }

  function put(address quote, uint amount) internal override returns (bool) {
    //optim
    if (amount == 0) {
      return true;
    }

    address cToken = isCompoundSourced[quote];
    (, uint cTokenBal, uint debt, ) =
      IcERC20(cToken).getAccountSnapshot(msg.sender);

    if (cToken != address(0)) {
      try this.supplyErc20ToCompound(cToken, amount) returns (bool success) {
        if (success) {
          return true;
        } else {
          emit ErrorOnDeposit(cToken, amount);
          return false;
        }
      } catch {
        emit UnexpErrorOnDeposit(cToken, amount);
        return false;
      }
    } //quote is not compound sourced
    return super.put(quote, amount); //trying other deposit methods
  }
}
