pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "./CompoundInterface.sol";

contract CompoundLender is MangroveOffer, Exponential {
  event UnexpErrorOnRedeem(address cToken, uint amount);
  event ErrorOnRedeem(address cToken, uint amount, uint errorCode);
  event UnexpErrorOnDeposit(address cToken, uint amount);
  event ErrorOnDeposit(address cToken, uint amount);

  // mapping : ERC20 -> cERC20
  mapping(address => address) public overlyings;
  mapping(address => bool) public compoundPut;
  mapping(address => bool) public compoundGet;

  // address of the comptroller
  IComptroller immutable public comptroller;

  // address of the price oracle used by the comptroller
  ICompoundPriceOracle immutable public oracle;

  constructor(address _comptroller, address payable _MGV) MangroveOffer(_MGV) {
    comptroller = IComptroller(_comptroller); // comptroller address
    oracle = IComptroller(_comptroller).oracle(); // pricefeed used by the comptroller
  }

  ///@notice To declare put/get methods should use Compound to manage token assets
  ///@param token address of the underlying token
  ///@param cToken address of the overlying token. Put 0x0 here to stop getting/putting token on Compound
  function _setCompoundSource(address token, address cToken)
    external
    onlyCaller(admin)
  {
    overlyings[token] = cToken;
  }

  function _setCompoundPut(address erc20, bool flag) external onlyCaller(admin) {
    compoundPut[erc20] = flag;
  }

  function _setCompoundGet(address erc20, bool flag) external onlyCaller(admin) {
    compoundGet[erc20] = flag;
  }


  function maxGettableUnderlying(IcERC20 cToken) internal view returns (uint, uint) {
    
    (uint , uint liquidity, uint) = comptroller.getAccountLiquidity(msg.sender);
    uint maxRedeemableUnderlying = divScalarByExpTruncate(
      liquidity,
      mulExp(
        Exp({exp:comptroller.markets(cToken).collateralFactorMantissa}),
        Exp({exp:oracle.getUnderlyingPrice(cToken)});
      )
    );
    return (liquidity,maxRedeemableUnderlying);
  }

  ///@notice method to get `base` during makerTrade
  ///@param base address of the ERC20 managing `base` token
  ///@param amount of token that the trade is still requiring
  function get(address base, uint amount) internal override returns (uint) {
    if (!_compoundGet[base]) { // if flag says not to fetch liquidity on compound
      return amount;
    }
    address base_cErc20 = _overlyings[base]; // this is 0x0 if base is not compound sourced.
    if (base_cErc20 == address(0)) { 
      return (0,0);
    }
    (uint, uint redeemable) = maxGettableUnderlying(base);  
    uint redeemAmount = redeemable > amount ? amount : redeemable;
    getInternal()
  
  }

  function getInternal(address cBase, uint amountToRedeem) internal returns (uint){
    try IcERC20(cBase).redeemUnderlying(amountToRedeem) returns (
        uint errorCode
      ) {
        if (errorCode == 0) {
          //compound redeem was a success
          return 0;
        } else {
          //ompound redeem failed
          emit ErrorOnRedeem(cBase, amountToRedeem, errorCode);
          return amountToRedeem;
        }
      } catch {
        emit UnexpErrorOnRedeem(base_cErc20, amountToRedeem);
        return amountToRedeem;
      }
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  // NB `_cErc20` contract MUST be approved to perform `transferFrom _erc20` by `this` contract.
  // `_cERC20` need not be `BASE_cERC` if LP wants to put quote payment into compound as well.
  function supplyErc20ToCompound(address cErc20, uint numTokensToSupply)
    external
    returns (bool success)
  {
    address underlying = IcERC20(cErc20).underlying();
    require(underlying != address(0), "Invalid cErc20 address");

    // Approve transfer on the ERC20 contract (not needed if cERC20 is already approved for `this`)
    IERC20(underlying).approve(cErc20, numTokensToSupply);

    // Mint cTokens
    uint mintResult = IcERC20(cErc20).mint(numTokensToSupply);
    success = (mintResult == 0);
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
