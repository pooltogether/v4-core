// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "./ITicket.sol";
import "./IDrawHistory.sol";
import "../PrizeDistributionHistory.sol";
import "../DrawPrizes.sol";
import "../libraries/DrawLib.sol";

/**
  * @title  PoolTogether V4 DrawCalculator
  * @author PoolTogether Inc Team
  * @notice The DrawCalculator interface.
*/
interface IDrawCalculator {

  struct PickPrize {
    bool won;
    uint8 distributionIndex;
  }

  ///@notice Emitted when the contract is initialized
  event Deployed(ITicket indexed ticket);

  ///@notice Emitted when the claimableDraw is set/updated
  event DrawPrizesSet(DrawPrizes indexed claimableDraw);

  /**
    * @notice Calulates the prize amount for a user for Multiple Draws. Typically called by a DrawPrizes.
    * @param user User for which to calcualte prize amount
    * @param drawIds draw array for which to calculate prize amounts for
    * @param data The encoded pick indices for all Draws. Expected to be just indices of winning claims. Populated values must be less than totalUserPicks.
    * @return List of awardable prizes ordered by linked drawId
   */
  function calculate(address user, uint32[] calldata drawIds, bytes calldata data) external view returns (uint256[] memory);

  /**
    * @notice Read global DrawHistory variable.
    * @return IDrawHistory
  */
  function getDrawHistory() external view returns (IDrawHistory);

  /**
    * @notice Read global DrawHistory variable.
    * @return IDrawHistory
  */
  function getPrizeDistributionHistory() external view returns (PrizeDistributionHistory);
  /**
    * @notice Set global DrawHistory reference.
    * @param _drawHistory DrawHistory address
    * @return New DrawHistory address
  */
  function setDrawHistory(IDrawHistory _drawHistory) external returns (IDrawHistory);
  
  /**
    * @notice Returns a users balances expressed as a fraction of the total supply over time.
    * @param _user The users address
    * @param _drawIds The drawsId to consider
    * @return Array of balances
  */
  function getNormalizedBalancesForDrawIds(address _user, uint32[] calldata _drawIds) external view returns (uint256[] memory);

  /**
    * @notice Returns a users balances expressed as a fraction of the total supply over time.
    * @param _user The user for which to calculate the distribution indices
    * @param _pickIndices The users pick indices for a draw
    * @param _drawId The draw for which to calculate the distribution indices
    * @return List of distributions for Draw.drawId
  */
  function checkPrizeDistributionIndicesForDrawId(address _user, uint64[] calldata _pickIndices, uint32 _drawId) external view returns(PickPrize[] memory);
}
