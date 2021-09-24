// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "../Reserve.sol";
import "./ERC20Mintable.sol";

contract ReserveHarness is Reserve {

  constructor(address _owner, IERC20 _token)
    Reserve(_owner, _token)
  {
  }

  function setObservationsAt(ObservationLib.Observation[] calldata observations) external {
    for(uint i = 0; i < observations.length; i++) {
      reserveAccumulators[i] = observations[i];
    }
    cardinality = uint16(observations.length);
  }

  function doubleCheckpoint(ERC20Mintable token, uint256 amount) external {
    _checkpoint();
    token.mint(address(this), amount);
    _checkpoint();
  }

}