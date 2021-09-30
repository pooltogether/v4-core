// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../libraries/DrawLib.sol";

interface IDrawHistory {
    /**
     * @notice Emit when a new draw has been created.
     * @param drawId Draw id
     * @param draw The Draw struct
     */
    event DrawSet(uint32 indexed drawId, DrawLib.Draw draw);

    /**
     * @notice Read a Draw from the draws ring buffer.
     * @dev    Read a Draw using the Draw.drawId to calculate position in the draws ring buffer.
     * @param drawId Draw.drawId
     * @return DrawLib.Draw
     */
    function getDraw(uint32 drawId) external view returns (DrawLib.Draw memory);

    /**
     * @notice Read multiple Draws from the draws ring buffer.
     * @dev    Read multiple Draws using each Draw.drawId to calculate position in the draws ring buffer.
     * @param drawIds Array of Draw.drawIds
     * @return DrawLib.Draw[]
     */
    function getDraws(uint32[] calldata drawIds) external view returns (DrawLib.Draw[] memory);

    /**
     * @notice Gets the number of Draws held in the draw ring buffer.
     * @dev If no Draws have been pushed, it will return 0.
     * @dev If the ring buffer is full, it will return the cardinality.
     * @dev Otherwise, it will return the NewestDraw index + 1.
     * @return Number of Draws held in the draw ring buffer.
     */
    function getDrawCount() external view returns (uint32);

    /**
     * @notice Read newest Draw from the draws ring buffer.
     * @dev    Uses the nextDrawIndex to calculate the most recently added Draw.
     * @return DrawLib.Draw
     */
    function getNewestDraw() external view returns (DrawLib.Draw memory);

    /**
     * @notice Read oldest Draw from the draws ring buffer.
     * @dev    Finds the oldest Draw by comparing and/or diffing totalDraws with the cardinality.
     * @return DrawLib.Draw
     */
    function getOldestDraw() external view returns (DrawLib.Draw memory);

    /**
     * @notice Push Draw onto draws ring buffer history.
     * @dev    Push new draw onto draws history via authorized manager or owner.
     * @param draw DrawLib.Draw
     * @return Draw.drawId
     */
    function pushDraw(DrawLib.Draw calldata draw) external returns (uint32);

    /**
     * @notice Set existing Draw in draws ring buffer with new parameters.
     * @dev    Updating a Draw should be used sparingly and only in the event an incorrect Draw parameter has been stored.
     * @param newDraw DrawLib.Draw
     * @return Draw.drawId
     */
    function setDraw(DrawLib.Draw calldata newDraw) external returns (uint32);
}
