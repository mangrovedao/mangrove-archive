pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

interface IcERC20 is IERC20 {
  /*** User Interface ***/
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
  function balanceOfUnderlying(address owner) external returns (uint);
  function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
  function borrowRatePerBlock() external view returns (uint);
  function supplyRatePerBlock() external view returns (uint);
  function totalBorrowsCurrent() external returns (uint);
  function borrowBalanceCurrent(address account) external returns (uint);
  function borrowBalanceStored(address account) external view returns (uint);
  function exchangeRateCurrent() external returns (uint);
  function exchangeRateStored() external view returns (uint);
  function getCash() external view returns (uint);
  function accrueInterest() external returns (uint);
  function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);
  function redeemUnderlying(uint redeemAmount) external returns (uint);
  function mint(uint mintAmount) external returns (uint);

  function underlying() external returns (address); // access to public variable containing the address of the underlying ERC20
  }

abstract contract CompoundSourced is MangroveOffer {
  address immutable BASE_cERC;
  bytes32 constant UNEXPECTEDERROR = "UNEXPECTEDERROR";
  bytes32 constant NOTREDEEMABLE = "NOTREDEEMABLE";

  constructor(address cToken) {
    BASE_cERC = cToken; //should check (IcERC20(_cERC20).underlying()==BASE_ERC upond deployment
  }

  // returns (Proceed, remaining underlying) + (Drop, [UNEXPECTEDERROR + Missing underlying])
  function trade_redeemCompoundBase(uint amount)
    internal
    returns (TradeResult, bytes32)
  {
    uint balance = IcERC20(BASE_cERC).balanceOfUnderlying(address(this));
    if (balance >= amount) {
      try IcERC20(BASE_cERC).redeemUnderlying(amount) returns (uint errorCode) {
        if (errorCode == 0) {
          return (TradeResult.Proceed, bytes32(balance - amount));
        } else {
          return (TradeResult.Drop, bytes32(errorCode));
        }
      } catch {
        return (TradeResult.Drop, UNEXPECTEDERROR);
      } 
    }
    return (TradeResult.Drop, NOTREDEEMABLE);
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  // NB `_cErc20` contract MUST be approved to perform `transferFrom _erc20` by `this` contract.
  // `_cERC20` need not be `BASE_cERC` if LP wants to put quote payment into compound as well.
  function supplyErc20ToCompound(
    address cToken,
    uint numTokensToSupply
  ) public returns (bool success) {
    address underlying = IcERC20(cToken).underlying();
    require (underlying != address(0), "Invalid cToken address");

    // Approve transfer on the ERC20 contract
    IERC20(underlying).approve(cToken, numTokensToSupply);

    // Mint cTokens
    uint mintResult = IcERC20(cToken).mint(numTokensToSupply);
    success = mintResult == 0;
  }
}

interface IaERC20 is IERC20 {
  /*** User Interface ***/
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
  function redeem(uint redeemTokens) external returns (uint);
  function isTransferAllowed(address user, uint amount) external view returns (bool);
}

interface AaveV1LendingPool {
  function deposit(address _reserve, uint256 _amount, uint16 _referralCode) external payable;
  function core() external returns (LendingPoolCore);
}

interface LendingPoolCore {
  function getReserveATokenAddress(address _reserve) external view returns (address);
}

abstract contract AaveV1Sourced is MangroveOffer {
  address immutable BASE_aERC;
  address immutable POOL;
  bytes32 constant UNREDEEMABLE = "NOTREDEEMABLE";
  bytes32 constant UNEXPECTEDERROR = "UNEXPECTEDERROR";

  constructor(address pool, address aERC20) {
    BASE_aERC = aERC20; // must check AaveV1LendingPool(pool).core().getReserveATokenAddress(BASE_ERC);
    POOL = pool;
    require(aERC20 != address(0), "Base erc has no overlying asset in given pool");
  }

  // returns (Proceed, remaining underlying) + (Drop, [UNEXPECTEDERROR + Missing underlying])
  function trade_redeemAaaveBase(uint amount)
    internal
    returns (TradeResult, bytes32)
  {
    IaERC20 aToken = IaERC20(BASE_aERC);
    if (aToken.isTransferAllowed(address(this), amount)) {
      try aToken.redeem(amount) {
        return (
          TradeResult.Proceed,
          bytes32(aToken.balanceOf(address(this)) - amount)
        );
      } catch {
        return (TradeResult.Drop, UNEXPECTEDERROR);
      }
    } else {
      return (TradeResult.Drop, UNREDEEMABLE);
    }
  }

  function supplyErc20ToAaveV1(
    address erc20,
    uint numTokensToSupply,
    uint referralCode
  ) public {
    require(uint16(referralCode)==referralCode,"Overflowing referral code");
    AaveV1LendingPool(POOL).deposit(erc20,numTokensToSupply,uint16(referralCode));
  }
  function supplyErc20ToAave(
    address erc20,
    uint numTokensToSupply
  ) public {
    AaveV1LendingPool(POOL).deposit(erc20,numTokensToSupply,uint16(0));
  }
  
}
