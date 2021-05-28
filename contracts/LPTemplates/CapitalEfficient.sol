pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

interface IcERC20 is IERC20 {
  /*** User Interface ***/
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
  function mint(uint amount) external returns (uint);

  function redeem(uint redeemTokens) external returns (uint);

  function redeemUnderlying(uint redeemAmount) external returns (uint);

  function borrow(uint borrowAmount) external returns (uint);

  function repayBorrow(uint repayAmount) external returns (uint);

  function balanceOfUnderlying(address owner) external returns (uint);
}

abstract contract CompoundSourced is MangroveOffer {
  IcERC20 immutable BASE_cERC;

  constructor(
    address payable mgv,
    address base_erc,
    address base_cErc
  ) MangroveOffer(mgv, base_erc) {
    BASE_cERC = IcERC20(base_cErc);
  }

  function trade_redeem(uint amount) internal returns (bool success) {
    success = BASE_cERC.redeemUnderlying(amount) == 0;
  }

  // adapted from https://medium.com/compound-finance/supplying-assets-to-the-compound-protocol-ec2cf5df5aa#afff
  // utility to supply erc20 to compound
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
