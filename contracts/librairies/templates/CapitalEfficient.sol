pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

abstract contract CompoundSourced is MangroveOffer {
  address immutable BASE_cERC;
  bytes32 constant UNEXPECTEDERROR = "UNEXPECTEDERROR";
  bytes32 constant NOTREDEEMABLE = "NOTREDEEMABLE";

  constructor(address _cERC20) {
    BASE_cERC = _cERC20;
  }

  // returns (Proceed, remaining underlying) + (Drop, [UNEXPECTEDERROR + Missing underlying])
  function __trade_redeemBase(uint amount)
    internal
    returns (TradeResult, bytes32)
  {
    uint balance = IcERC20(BASE_cERC).balanceOfUnderlying(address(this));
    if (balance >= amount) {
      uint errorCode = IcERC20(BASE_cERC).redeemUnderlying(amount);
      if (errorCode == 0) {
        return (TradeResult.Proceed, bytes32(balance - amount));
      } else {
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
    address _erc20,
    address _cErc20,
    uint _numTokensToSupply
  ) public returns (bool success) {
    // Create a reference to the underlying asset contract, like DAI.
    IERC20 underlying = IERC20(_erc20);

    // Create a reference to the corresponding cToken contract, like cDAI
    IcERC20 cToken = IcERC20(_cErc20);

    // Approve transfer on the ERC20 contract
    underlying.approve(_cErc20, _numTokensToSupply);

    // Mint cTokens
    uint mintResult = cToken.mint(_numTokensToSupply);
    success = mintResult == 0;
  }
}

abstract contract AaveSourced is MangroveOffer {
  address immutable BASE_aERC;
  bytes32 constant UNREDEEMABLE = "NOTREDEEMABLE";
  bytes32 constant UNEXPECTEDERROR = "UNEXPECTEDERROR";

  constructor(address _aERC20) {
    BASE_aERC = _aERC20;
  }

  // returns (Proceed, remaining underlying) + (Drop, [UNEXPECTEDERROR + Missing underlying])
  function __trade_redeemBase(uint amount)
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

  function supplyErc20ToAave(
    address _erc20,
    address _aErc20,
    uint _numTokensToSupply
  ) external returns (bool success) {}
}
