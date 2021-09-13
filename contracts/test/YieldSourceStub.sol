pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@pooltogether/yield-source-interface/contracts/IYieldSource.sol";

interface YieldSourceStub is IYieldSource {
  function canAwardExternal(address _externalToken) external view returns (bool);
}
