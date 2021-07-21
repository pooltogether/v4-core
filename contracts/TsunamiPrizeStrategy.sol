// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import "hardhat/console.sol";
// Libraries & Inheritance

interface IWaveModel {
  function calculate(uint256 randomNumber, uint256 prize, uint256 totalSupply, uint256 balance, bytes32 userRandomNumber, uint256[] calldata picks) external returns (uint256);
}

contract TsunamiPrizeStrategy {
  uint256 currentDrawId;
  uint256 currentDrawIndex;

  mapping(address => bytes32) internal claimedDraws;

  IWaveModel waveModel;

  struct Draw {
    uint256 randomNumber;
    uint256 timestamp;
    uint256 totalSupply;
    uint256 prize;
  }

  function setWaveModel(IWaveModel _waveModel) external {
    waveModel = _waveModel;
  }

  /* ============ External Functions ============ */

  /**
     * @notice Claim award prize passing by passing user draws and pick indices. 
    */
  function claim(address user, uint256[] calldata timestamps, uint256[] calldata balances, bytes calldata data) external {
    _claim(user, timestamps, balances, data);
  }

  
  /* ============ Internal Functions ============ */

  event Claimed (
    address indexed user,
    bytes32 userClaimedDraws,
    uint256 prize
  );

  /**
    * @dev Award users with prize by calculating total winners via the external model.
    *
  */
  function _claim(address user, uint256[] memory timestamps, uint256[] memory balances, bytes memory data) internal {
    uint256[][] memory pickIndices = abi.decode(data, (uint256 [][]));

    bytes32 userClaimedDraws = claimedDraws[user];
    uint256 prize;

    uint256 _currentDrawId = currentDrawId;
    bytes32 userRandomNumber = keccak256(abi.encodePacked(user));

    for (uint256 index = 0; index < timestamps.length; index++) {
      (Draw memory draw, uint256 drawId) = _findDraw(timestamps[index]);

      prize += waveModel.calculate(draw.randomNumber, draw.prize, draw.totalSupply, balances[index], userRandomNumber, pickIndices[index]);

      // userClaimedDraws // MAGIC
      userClaimedDraws = _claimDraw(userClaimedDraws, drawId, _currentDrawId);
    }

    claimedDraws[user] = userClaimedDraws;
    emit Claimed(user, userClaimedDraws, prize);
  }

  function _findDraw(uint256 timestamp) internal virtual returns (Draw memory draw, uint256 drawId) {

  }

  function _claimDraw(bytes32 userClaimedDraws, uint256 drawId, uint256 _currentDrawId) internal returns (bytes32) {
    require(drawId + 256 > _currentDrawId, 'ERROR');
    require(drawId <= _currentDrawId, 'ERROR2');

    // How many indices in the past the given draw is
    uint256 deltaIndex = _currentDrawId - drawId;

    // Find absolute draw index by using currentDraw index and delta
    uint8 drawIndex = uint8(currentDrawIndex - deltaIndex);
    bool isClaimed = _readLastClaimFromClaimedHistory(userClaimedDraws, drawIndex);

    require(!isClaimed, "ERROR3");

    return _writeLastClaimFromClaimedHistory(userClaimedDraws, drawIndex);
  }

  function _readLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) internal pure returns (bool) {
    uint256 mask = (uint256(1)) << (_drawIndex);
    return ((uint256(_userClaimedDraws) & mask) >> (_drawIndex)) != 0;    
  }

  /// @notice Updates a 256 bit word with a 32 bit representation of a block number at a particular index
  /// @param _userClaimedDraws The 256 word
  /// @param _drawIndex The index within that word (0 to 7)
  function _writeLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) internal pure returns (bytes32) { 
    uint256 mask =  (uint256(1)) << (_drawIndex);
    return bytes32(uint256(_userClaimedDraws) | mask); 
  }
}