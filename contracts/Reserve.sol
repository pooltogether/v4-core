// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./interfaces/IReserve.sol";
import "./libraries/ObservationLib.sol";
import "./libraries/RingBuffer.sol";

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Reserve is IReserve, Manageable {

    using SafeERC20 for IERC20;
    
    
    IERC20 public immutable token;

    uint224 public withdrawAccumulator;

    ObservationLib.Observation[65535] public reserveAccumulator;

    uint256 public reserveAccumulatorCardinality;
    

    /* ============ Events ============ */
    event Deployed(IERC20 indexed token);

    /* ============ Constructor ============ */
    
    constructor(address _owner, IERC20 _token) Ownable(_owner){
        
        
        token = _token;
        emit Deployed(_token);
    }

    /* ============ External Functions ============ */
    function withdrawTo(address recipient, uint256 amount) external override onlyManagerOrOwner {
        // first checkpoint
        _checkpoint();
        token.safeTransfer(recipient, amount);
    }
    
    function checkpoint() external override {
        _checkpoint();
    }    
    
    function getReserveBetween(uint32 startTimestamp, uint32 endTimestamp) external override view returns (uint224) {

        uint32 timeNow = uint32(block.timestamp);
        uint256 _reserveAccumulatorCardinality = reserveAccumulatorCardinality;
        
        (ObservationLib.Observation memory startBeforeOrAt, ObservationLib.Observation memory startAtOrAfter) = 
            ObservationLib.binarySearch(reserveAccumulator, _reserveAccumulatorCardinality - 1, 0, startTimestamp, _reserveAccumulatorCardinality, timeNow);

        (ObservationLib.Observation memory endBeforeOrAt, ObservationLib.Observation memory endAtOrAfter) = 
            ObservationLib.binarySearch(reserveAccumulator, _reserveAccumulatorCardinality - 1, 0, endTimestamp, _reserveAccumulatorCardinality, timeNow);

        // if we have exact observations for startTimestamp return them
        if(startAtOfAfter.timestamp == startTimestamp){
            return startAtOrAfter.amount;
        }
        else if(startBeforeOfAt.timestamp == startTimestamp){
            return startBeforeOrAt.amount;
        }

        // if startTimestamp is before the first observation return 0 vals
        if(startTimestamp < startBeforeOrAt.timestamp){
            return uint224(0); // balanceOf(address(this))?? for no checkpoint but there is a balance
        }

        // if endTimstamp is at or after the last observation return the last observation  
        if(endAtOrAfter.timestamp == endTimestamp){
            return endAtOrAfter.amount;
        }
        else if (endTimestamp >= endBeforeOrAt.timestamp){
            return endBeforeOrAt.amount;
        }

        // cases where we have observations between startTimestamp and endTimestamp
        






    }
    
    function getReservesBetween(uint32[] calldata startTimestamp, uint32[] calldata endTimestamp) external override view returns (uint256[] memory){

    }

    /* ============ Internal Functions ============ */
    function _checkpoint() internal {
        /*
        if (balanceOf() + withdrawal_acc > reserve_acc)
	        Reserve_acc += (balanceOf() + withdrawal_acc - reserve_acc)

        */

        uint256 balanceOfReserve = token.balanceOf(address(this));
        uint224 _withdrawAccumulator = withdrawAccumulator; //sload


        ObservationLib.Observation memory _reserveAccumulator;

        uint256 _reserveAccumulatorCardinality = reserveAccumulatorCardinality;

        if (_reserveAccumulatorCardinality > 0) {
            _reserveAccumulator = reserveAccumulator[_reserveAccumulatorCardinality - 1];    
        }

        
        if(balanceOfReserve + _withdrawAccumulator > _reserveAccumulator.amount){
            
            uint32 now = uint32(block.timestamp);
            uint224 newReserveAccumulator = uint224(balanceOfReserve) + _withdrawAccumulator - _reserveAccumulator.amount;
            // store next observation
            reserveAccumulator[_reserveAccumulatorCardinality] = ObservationLib.Observation({
                amount: newReserveAccumulator, 
                timestamp: now
            });

            reserveAccumulatorCardinality++;

            emit Checkpoint(now, newReserveAccumulator, _withdrawAccumulator);
        }


        
    }   


}