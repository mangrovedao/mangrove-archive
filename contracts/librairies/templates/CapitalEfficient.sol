pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

interface IcERC20 is IERC20 {
  /*** User Interface ***/
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
  function balanceOfUnderlying(address owner) external returns (uint);

  function getAccountSnapshot(address account)
    external
    view
    returns (
      uint,
      uint,
      uint,
      uint
    );

  function borrowRatePerBlock() external view returns (uint);

  function supplyRatePerBlock() external view returns (uint);

  function totalBorrowsCurrent() external returns (uint);

  function borrowBalanceCurrent(address account) external returns (uint);

  function borrowBalanceStored(address account) external view returns (uint);

  function exchangeRateCurrent() external returns (uint);

  function exchangeRateStored() external view returns (uint);

  function getCash() external view returns (uint);

  function accrueInterest() external returns (uint);

  function seize(
    address liquidator,
    address borrower,
    uint seizeTokens
  ) external returns (uint);

  function redeemUnderlying(uint redeemAmount) external returns (uint);

  function mint(uint mintAmount) external returns (uint);

  function underlying() external returns (address); // access to public variable containing the address of the underlying ERC20
}

abstract contract CompoundSourced is MangroveOffer {

  event UnexpErrorOnRedeem(address cToken, uint amount);
  event ErrorOnRedeem(address cToken, uint amount, uint errorCode);

  /// @dev isCompoundSourced[erc20]=cERC20 if erc20 is not solely stored in `this` contract but on Compound as well
  mapping (address => address) private isCompoundSourced;

  /// @param minCompoundReserve is the minimal amount of token needed to trigger a compound redeem/deposit
  uint private minCompoundReserve;

  function setMinReserve(uint min) external onlyCaller(admin) {
    minCompoundReserve = min;
  }

  function setCompoundSource(address token, address cToken) external onlyCaller(admin) {
    isCompoundSourced[token] = cToken;
  }

  function withdraw(address base, uint amount)
    internal
    returns (uint)
  {
    uint stillToBeFetched = !super.withdraw(base,amount); 

    if (
      stillToBeFetched == 0 /// @dev test this first to avoid storage reads
    || stillToBeFetched <= minCompoundReserve 
    ){
      return stillToBeFetched;
    }
    else {
      address base_cErc20 = isCompoundSourced[base]; ///@dev this is 0x0 if base is not compound sourced.
      if (base_cErc20 == address(0)) {return stillToBeFetched;} /// @dev not tested earlier to avoid storage read

      uint compoundBalance = IcERC20(base_cErc20).balanceOfUnderlying(address(this));
      uint redeemAmount = compoundBalance >= stillToBeFetched ? stillToBeFetched : compoundBalance ; 
      try IcERC20(base_cErc20).redeemUnderlying(redeemAmount) returns (uint errorCode) {
        if (errorCode == 0) { /// @dev compound redeem was a success
          return (stillToBeFetched-redeemAmount);
        } else { /// @dev compound redeem failed
          emit ErrorOnRedeem(base_cErc20,redeemAmount,errorCode);
          return stillToBeFetched;
        }
      } catch {
        emit UnexpErrorOnRedeem(base_cErc20,redeemAmount);
        return stillToBeFetched;
      }
    }
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  // NB `_cErc20` contract MUST be approved to perform `transferFrom _erc20` by `this` contract.
  // `_cERC20` need not be `BASE_cERC` if LP wants to put quote payment into compound as well.
  function supplyErc20ToCompound(address cErc20, uint numTokensToSupply)
    public
    returns (bool success)
  {
    address underlying = IcERC20(cErc20).underlying();
    require(underlying != address(0), "Invalid cErc20 address");

    // Approve transfer on the ERC20 contract
    IERC20(underlying).approve(cErc20, numTokensToSupply);

    // Mint cTokens
    uint mintResult = IcERC20(cErc20).mint(numTokensToSupply);
    success = (mintResult == 0);
  }

  function deposit(quote, amount) {
    /// @dev optim
    if (amount == 0) {return true;}

    if (amount >= minCompoundReserve){
      uint cToken = isCompoundSourced[quote];
      if (cToken != address(0)){
        try supplyErc20ToCompound(cToken, amount) returns (bool success) {
          if (success) {
            return true;
          }
          else {
            emit ErrorOnDeposit(cToken,amount);
            return false;
          }
        } catch {
          emit UnexpErrorOnDepost(cToken, amount);
          return false;
        }
      } /// @dev quote is not compound sourced
    } /// @dev ... or amount to deposit is too low to trigger a compound call
    return super.deposit(quote,amount); /// @dev trying other deposit methods
  }
}


interface IaERC20 is IERC20 {
  /*** User Interface ***/
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
  function redeem(uint redeemTokens) external returns (uint);

  function isTransferAllowed(address user, uint amount)
    external
    view
    returns (bool);
}

interface AaveV1LendingPool {
  function deposit(
    address _reserve,
    uint _amount,
    uint16 _referralCode
  ) external payable;

  function core() external returns (LendingPoolCore);
}

interface LendingPoolCore {
  function getReserveATokenAddress(address _reserve)
    external
    view
    returns (address);
}

abstract contract AaveV1Sourced is MangroveOffer {
  address immutable POOL;
  bytes32 constant UNREDEEMABLE = "NOTREDEEMABLE";
  bytes32 constant UNEXPECTEDERROR = "UNEXPECTEDERROR";

  constructor(address pool) {
    POOL = pool;
  }

  // returns (Proceed, remaining underlying) + (Drop, [UNEXPECTEDERROR + Missing underlying])
  function trade_redeemAaveV1Base(address base_aErc20, uint amount)
    internal
    returns (TradeResult, bytes32)
  {
    IaERC20 aToken = IaERC20(base_aErc20);
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
    require(uint16(referralCode) == referralCode, "Overflowing referral code");
    AaveV1LendingPool(POOL).deposit(
      erc20,
      numTokensToSupply,
      uint16(referralCode)
    );
  }

  function supplyErc20ToAave(address erc20, uint numTokensToSupply) public {
    AaveV1LendingPool(POOL).deposit(erc20, numTokensToSupply, uint16(0));
  }
}

interface AaveLendingPool {
  function deposit(
    address asset,
    uint amount,
    address onBehalfOf,
    uint16 referralCode
  ) external;
}

abstract contract AaveSourced is MangroveOffer {
  address immutable POOL;
  bytes32 constant UNREDEEMABLE = "NOTREDEEMABLE";
  bytes32 constant UNEXPECTEDERROR = "UNEXPECTEDERROR";

  constructor(address pool) {
    POOL = pool;
  }

  // returns (Proceed, remaining underlying) + (Drop, [UNEXPECTEDERROR + Missing underlying])
  function trade_redeemAaveBase(uint amount)
    internal
    returns (TradeResult, bytes32)
  {}

  // function supplyErc20ToAaveV(
  //   address erc20,
  //   uint numTokensToSupply,
  //   uint referralCode
  // ) public {
  //   require(uint16(referralCode)==referralCode,"Overflowing referral code");
  //   AaveV1LendingPool(POOL).deposit(erc20,numTokensToSupply,uint16(referralCode));
  // }
  // function supplyErc20ToAave(
  //   address erc20,
  //   uint numTokensToSupply
  // ) public {
  //   AaveV1LendingPool(POOL).deposit(erc20,numTokensToSupply,uint16(0));
  // }
}
