pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

abstract contract CompoundSourced is MangroveOffer {
  IcERC20 immutable BASE_cERC;
  bytes32 constant UNEXPECTEDERROR = "Unexpected error";

  constructor(address base_cErc) {
    BASE_cERC = IcERC20(base_cErc);
  }

  // returns (Proceed, remaining underlying) + (Drop, [UNEXPECTEDERROR + Missing underlying])
  function __trade_redeemBase(uint amount) internal returns (TradeResult, bytes32) {
    uint balance = BASE_cERC.balanceOfUnderlying(address(this));
    if (balance >= amount) {
      uint errorCode = BASE_cERC.redeemUnderlying(amount);
      if (errorCode == 0) {
        return (TradeResult.Proceed, bytes32(balance - amount));
      }
      else {
        return (TradeResult.Drop, UNEXPECTEDERROR);
      }
    }
    return (TradeResult.Drop, bytes32(amount - balance));
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
