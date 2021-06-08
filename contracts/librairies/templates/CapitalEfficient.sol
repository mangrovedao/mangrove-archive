pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "./CompoundInterface.sol";

contract CompoundSourced is MangroveOffer {
  event UnexpErrorOnRedeem(address cToken, uint amount);
  event ErrorOnRedeem(address cToken, uint amount, uint errorCode);
  event UnexpErrorOnDeposit(address cToken, uint amount);
  event ErrorOnDeposit(address cToken, uint amount);

  // mapping : ERC20 -> cERC20
  mapping(address => address) private isCompoundSourced;

  // address of the comptroller
  IComptroller immutable comptroller;

  // address of the price oracle used by the comptroller
  ICompoundPriceOracle immutable oracle;

  constructor(address _comptroller, address payable _MGV) MangroveOffer(_MGV) {
    comptroller = IComptroller(_comptroller);
    oracle = IComptroller(_comptroller).oracle();
  }

  function setCompoundSource(address token, address cToken)
    external
    onlyCaller(admin)
  {
    isCompoundSourced[token] = cToken;
  }

  ///@notice note that the above method might fail if user is not a borrower because balanceOfUnderlying does not take into account underlying that is used as a collateral
  function get(address base, uint amount) internal override returns (uint) {
    uint stillToBeFetched = super.get(base, amount); //first tries to get available liquidity with higher priority

    if (stillToBeFetched == 0) {
      return stillToBeFetched;
    } else {
      address base_cErc20 = isCompoundSourced[base]; // this is 0x0 if base is not compound sourced.
      if (base_cErc20 == address(0)) {
        return stillToBeFetched;
      } //not tested earlier to avoid storage read

      uint compoundBalance =
        IcERC20(base_cErc20).balanceOfUnderlying(address(this));
      uint redeemAmount =
        compoundBalance >= stillToBeFetched
          ? stillToBeFetched
          : compoundBalance;
      try IcERC20(base_cErc20).redeemUnderlying(redeemAmount) returns (
        uint errorCode
      ) {
        if (errorCode == 0) {
          //compound redeem was a success
          return (stillToBeFetched - redeemAmount);
        } else {
          //ompound redeem failed
          emit ErrorOnRedeem(base_cErc20, redeemAmount, errorCode);
          return stillToBeFetched;
        }
      } catch {
        emit UnexpErrorOnRedeem(base_cErc20, redeemAmount);
        return stillToBeFetched;
      }
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
