import "../Reserve.sol";
import "./ERC20Mintable.sol";

contract ReserveHarness is Reserve {

  constructor(address _owner, IERC20 _token)
    Reserve(_owner, _token)
  {

  }

  function __getReserveAccumulatedAt(uint32 timestamp) external view returns (uint224) {
    return _getReserveAccumulatedAt(timestamp);
  }

  function setObservationsAt(ObservationLib.Observation[] calldata observations) external {
    for(uint i = 0; i < observations.length; i++) {
      reserveAccumulator[i] = observations[i];
    }
    reserveAccumulatorCardinality = uint16(observations.length);
  }

  function doubleCheckpoint(ERC20Mintable token, uint256 amount) external {
    _checkpoint();
    token.mint(address(this), amount);
    _checkpoint();
  }

  function getReserveAccumulatorCardinality() external view returns (uint16) {
    return reserveAccumulatorCardinality;
  }


}