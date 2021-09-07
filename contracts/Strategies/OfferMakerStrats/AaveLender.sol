pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../interfaces/Aave/ILendingPool.sol";
import "../interfaces/Aave/ILendingPoolAddressesProvider.sol";
import "../interfaces/Aave/IPriceOracleGetter.sol";


import "hardhat/console.sol";

// SPDX-License-Identifier: MIT

contract AaveLender is MangroveOffer {
  event ErrorOnRedeem(address ctoken, uint amount);
  event ErrorOnMint(address ctoken, uint amount);

  // address of the lendingPool
  ILendingPool public immutable lendingPool;
  IPriceOracleGetter public immutable priceOracle;
  uint16 referralCode;
  constructor(
    address _addressesProvider,
    address payable _MGV,
    uint _referralCode
  ) MangroveOffer(_MGV) {
    require(uint16(_referralCode) != _referralCode);
    referralCode = uint16(referralCode); // for aave reference, put 0 for tests
    address _lendingPool = ILendingPoolAddressesProvider(_addressesProvider).getLendingPool();
    address _priceOracle = ILendingPoolAddressesProvider(_addressesProvider).getPriceOracle();
    require(_lendingPool != address(0), "Invalid lendingPool address");
    require(_priceOracle != address(0), "Invalid priceOracle address");
    lendingPool = ILendingPool(_lendingPool);
    priceOracle = IPriceOracleGetter(_priceOracle);
  }

  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with Aave
  /**************************************************************************/

  ///@notice approval of ctoken contract by the underlying is necessary for minting and repaying borrow
  ///@notice user must use this function to do so.
  function approveLendingPool(IERC20 token, uint amount) external onlyAdmin {
    token.approve(address(lendingPool), amount);
  }

  function mint(IERC20 underlying, uint amount) external onlyAdmin {
    aaveMint(underlying, amount);
  }

  function redeem(IERC20 underlying, uint amount) external onlyAdmin {
    aaveRedeem(underlying,amount);
  }

  ///@notice exits markets
  function exitMarket(IERC20 underlying) external onlyAdmin {
    lendingPool.setUserUseReserveAsCollateral(address(underlying), false);
  }

  function enterMarket(IERC20 underlying) external onlyAdmin {
    lendingPool.setUserUseReserveAsCollateral(address(underlying), true);
  }

  function isPooled(IERC20 asset) public view returns (bool){
    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(address(asset));
    DataTypes.UserConfigurationMap memory cfg = lendingPool.getUserConfiguration(address(this));
    return DataTypes.isUsingAsCollateral(cfg,reserveData.id);
  }

  // structs to avoir stack too deep in maxGettableUnderlying
  struct Underlying {
    uint ltv;
    uint liquidationThreshold;
    uint decimals;
    uint price;
  }

  struct Account {
    uint collateral;
    uint debt;
    uint borrowPower;
    uint redeemPower;
    uint ltv;
    uint liquidationThreshold;
    uint health;
    uint balanceOfUnderlying;
  }

  /// @notice Computes maximal borrow capacity of the account and maximal redeem capacity
  /// return (maxRedeemableUnderlying, maxBorrowableUnderlying|maxRedeemed)

  function maxGettableUnderlying(IERC20 asset)
    public
    view
    returns (uint, uint)
  {
    Underlying memory underlying; // asset parameters
    Account memory account; // accound parameters
    (
      account.collateral,
      account.debt, 
      account.borrowPower,  // avgLtv * sumCollateralEth - sumDebtEth
      account.liquidationThreshold, 
      account.ltv, 
      account.health // avgLiquidityThreshold * sumCollateralEth / sumDebtEth  -- should be less than 10**18
      ) = lendingPool.getUserAccountData(address(this));
      DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(address(asset));
      (
        underlying.ltv, // collateral factor for lending
        underlying.liquidationThreshold,  // collateral factor for borrowing
        /*liquidationBonus*/,
        underlying.decimals,
        /*reserveFactor*/
      ) = DataTypes.getParams(reserveData.configuration);
      account.balanceOfUnderlying = IERC20(reserveData.aTokenAddress).balanceOf(address(this));
      underlying.price = div_(
        IPriceOracleGetter(priceOracle).getAssetPrice(address(asset)),
        10**underlying.decimals
      );

      // account.redeemPower = account.liquidationThreshold * account.collateral - account.debt
      account.redeemPower = sub_(
        mul_(
          account.liquidationThreshold,
          account.collateral
        ),
        account.debt
      );
      // max redeem capacity = account.redeemPower/ underlying.liquidationThreshold * underlying.price
      // unless account doesn't have enough collateral in asset token
      uint maxRedeemableUnderlying = min(
        div_(
          account.redeemPower,
          mul_(
            underlying.liquidationThreshold,
            underlying.price
          )
        ),
        account.balanceOfUnderlying
      );
      // computing max borrow capacity on the premisses that maxRedeemableUnderlying has been redeemed.
      // max borrow capacity = (account.borrowPower - (ltv*redeemed)) / underlying.ltv * underlying.price
      uint maxBorrowAfterRedeem = div_(
        sub_(
          account.borrowPower,
          maxRedeemableUnderlying * underlying.ltv
        ),
        mul_(
          underlying.ltv,
          underlying.price
        )
      );
      return (maxRedeemableUnderlying, maxBorrowAfterRedeem);
  }

  ///@notice method to get `base` during makerExecute
  ///@param base address of the ERC20 managing `base` token
  ///@param amount of token that the trade is still requiring
  function __get__(IERC20 base, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    if (!isPooled(base)) {
      // if flag says not to fetch liquidity on compound
      return amount;
    }
    (uint redeemable, /*maxBorrowAfterRedeem*/) = maxGettableUnderlying(base);

    uint redeemAmount = min(redeemable, amount);

    if (aaveRedeem(base, redeemAmount) == 0) {
      // redeemAmount was transfered to `this`
      return (amount - redeemAmount);
    }
    return amount;
  }

  function aaveRedeem(IERC20 asset, uint amountToRedeem)
    internal
    returns (uint)
  {
    try lendingPool.withdraw(address(asset),amountToRedeem,address(this)) returns (uint withdrawn) {
      //aave redeem was a success
      if (amountToRedeem == withdrawn) {
        return 0;
      }
      else {
        emit ErrorOnRedeem(address(asset), amountToRedeem);
        return (amountToRedeem-withdrawn);
      }
    } catch {
      //compound redeem failed
      emit ErrorOnRedeem(address(asset), amountToRedeem);
      return amountToRedeem;
    }
  }

  function __put__(IERC20 quote, uint amount) internal virtual override {
    //optim
    if (amount == 0 || !isPooled(quote)) {
      return;
    }
    aaveMint(quote, amount);
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
  // NB `ctoken` contract MUST be approved to perform `transferFrom token` by `this` contract.
  /// @notice user need to approve ctoken in order to mint
  function aaveMint(IERC20 quote, uint amount) internal {
      // contract must haveallowance()to spend funds on behalf ofmsg.sender for at-leastamount for the asset being deposited. This can be done via the standard ERC20 approve() method.
      try lendingPool.deposit(address(quote), amount, address(this), referralCode) {
        return;
      } catch {
        emit ErrorOnMint(address(quote), amount);
      }
  }

}