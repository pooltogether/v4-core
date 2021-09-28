// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.6;
import "@pooltogether/owner-manager-contracts/contracts/Ownable.sol";
import "../interfaces/IPrizeSplit.sol";

/**
  * @title PrizeSplit Interface
  * @author PoolTogether Inc Team
*/
abstract contract PrizeSplit is IPrizeSplit, Ownable {

  /* ============ Global Variables ============ */
  PrizeSplitConfig[] internal _prizeSplits;
  

  /* ============ External Functions ============ */

  /// @inheritdoc IPrizeSplit
  function getPrizeSplit(uint256 prizeSplitIndex) external view override returns (PrizeSplitConfig memory) {
    return _prizeSplits[prizeSplitIndex];
  }

  /// @inheritdoc IPrizeSplit
  function getPrizeSplits() external view override returns (PrizeSplitConfig[] memory) {
    return _prizeSplits;
  }

  /// @inheritdoc IPrizeSplit
  function setPrizeSplits(PrizeSplitConfig[] calldata newPrizeSplits) external override onlyOwner {
    uint256 newPrizeSplitsLength = newPrizeSplits.length;

    // Add and/or update prize split configs using newPrizeSplits PrizeSplitConfig structs array.
    for (uint256 index = 0; index < newPrizeSplitsLength; index++) {
      PrizeSplitConfig memory split = newPrizeSplits[index];

      // REVERT when setting the canonical burn address.
      require(split.target != address(0), "PrizeSplit/invalid-prizesplit-target");

      // IF the CURRENT prizeSplits length is below the NEW prizeSplits
      // PUSH the PrizeSplit struct to end of the list.
      if (_prizeSplits.length <= index) {
        _prizeSplits.push(split);
      } else {
        // ELSE update an existing PrizeSplit struct with new parameters
        PrizeSplitConfig memory currentSplit = _prizeSplits[index];

        // IF new PrizeSplit DOES NOT match the current PrizeSplit
        // WRITE to STORAGE with the new PrizeSplit
        if (split.target != currentSplit.target || split.percentage != currentSplit.percentage) {
          _prizeSplits[index] = split;
        } else {
          continue;
        }
      }

      // Emit the added/updated prize split config.
      emit PrizeSplitSet(split.target, split.percentage, index);
    }

    // Remove old prize splits configs. Match storage _prizesSplits.length with the passed newPrizeSplits.length
    while (_prizeSplits.length > newPrizeSplitsLength) {
      uint256 _index = _prizeSplits.length - 1;
      _prizeSplits.pop();
      emit PrizeSplitRemoved(_index);
    }

    // Total prize split do not exceed 100%
    uint256 totalPercentage = _totalPrizeSplitPercentageAmount();
    require(totalPercentage <= 1000, "PrizeSplit/invalid-prizesplit-percentage-total");
  }

  /// @inheritdoc IPrizeSplit
  function setPrizeSplit(PrizeSplitConfig memory prizeStrategySplit, uint8 prizeSplitIndex) external override onlyOwner {
    require(prizeSplitIndex < _prizeSplits.length, "PrizeSplit/nonexistent-prizesplit");
    require(prizeStrategySplit.target != address(0), "PrizeSplit/invalid-prizesplit-target");

    // Update the prize split config
    _prizeSplits[prizeSplitIndex] = prizeStrategySplit;

    // Total prize split do not exceed 100%
    uint256 totalPercentage = _totalPrizeSplitPercentageAmount();
    require(totalPercentage <= 1000, "PrizeSplit/invalid-prizesplit-percentage-total");

    // Emit updated prize split config
    emit PrizeSplitSet(prizeStrategySplit.target, prizeStrategySplit.percentage, prizeSplitIndex);
  }

  /* ============ Internal Functions ============ */

  /**
  * @notice Calculate single prize split distribution amount.
  * @dev Calculate single prize split distribution amount using the total prize amount and prize split percentage.
  * @param amount Total prize award distribution amount
  * @param percentage Percentage with single decimal precision using 0-1000 ranges
  */
  function _getPrizeSplitAmount(uint256 amount, uint16 percentage) internal pure returns (uint256) {
    return (amount * percentage) / 1000;
  }

  /**
  * @notice Calculates total prize split percentage amount.
  * @dev Calculates total PrizeSplitConfig percentage(s) amount. Used to check the total does not exceed 100% of award distribution.
  * @return Total prize split(s) percentage amount
  */
  function _totalPrizeSplitPercentageAmount() internal view returns (uint256) {
    uint256 _tempTotalPercentage;
    uint256 prizeSplitsLength = _prizeSplits.length;
    for (uint8 index = 0; index < prizeSplitsLength; index++) {
      PrizeSplitConfig memory split = _prizeSplits[index];
      _tempTotalPercentage = _tempTotalPercentage +split.percentage;
    }
    return _tempTotalPercentage;
  }

  /**
  * @notice Distributes prize split(s).
  * @dev Distributes prize split(s) by awarding ticket or sponsorship tokens.
  * @param prize Starting prize award amount
  * @return Total prize award distribution amount exlcuding the awarded prize split(s)
  */
  function _distributePrizeSplits(uint256 prize) internal returns (uint256) {
    // Store temporary total prize amount for multiple calculations using initial prize amount.
    uint256 _prizeTemp = prize;
    uint256 prizeSplitsLength = _prizeSplits.length;
    for (uint256 index = 0; index < prizeSplitsLength; index++) {
      PrizeSplitConfig memory split = _prizeSplits[index];
      uint256 _splitAmount = _getPrizeSplitAmount(_prizeTemp, split.percentage);

      // Award the prize split distribution amount.
      _awardPrizeSplitAmount(split.target, _splitAmount);

      // Update the remaining prize amount after distributing the prize split percentage.
      prize = prize - _splitAmount;
    }

    return prize;
  }

  /**
    * @notice Mints ticket or sponsorship tokens to prize split recipient.
    * @dev Mints ticket or sponsorship tokens to prize split recipient via the linked PrizePool contract.
    * @param target Recipient of minted tokens
    * @param amount Amount of minted tokens
  */
  function _awardPrizeSplitAmount(address target, uint256 amount) virtual internal;

}
