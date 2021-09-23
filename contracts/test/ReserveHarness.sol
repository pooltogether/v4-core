import "../Reserve.sol";

contract ReserveHarness is Reserve {

  function __getReserveAccumulatedAt(uint32 timestamp) external view returns (uint224) {
    return _getReserveAccumulatedAt(timestamp);
  }

}