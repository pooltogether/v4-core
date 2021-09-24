// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./interfaces/IReserve.sol";
import "./libraries/ObservationLib.sol";
import "./libraries/RingBuffer.sol";

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
  * @title  PoolTogether V4 Reserve
  * @author PoolTogether Inc Team
  * @notice The Reserve migrates allotments of token distributions.
*/
contract Reserve is IReserve, Manageable {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable token;

    uint224 public withdrawAccumulator;

    ObservationLib.Observation[65535] internal reserveAccumulators;

    uint16 internal cardinality;
    
    /* ============ Events ============ */

    event Deployed(IERC20 indexed token);

    /* ============ Constructor ============ */
    
    constructor(address _owner, IERC20 _token) Ownable(_owner) {
        token = _token;
        emit Deployed(_token);
    }

    /* ============ External Functions ============ */
    
    /**
      * @notice Create observation checkpoint in ring bufferr.
      * @dev    Calculates total desposited tokens since last checkpoint and creates new accumulator checkpoint.
     */
    function checkpoint() external override {
        _checkpoint();
    }

    /**
      * @notice Read global CARDINALITY value.
      * @return Ring buffer range (i.e. CARDINALITY) 
     */
    function getCardinality() external view returns (uint16) {
        return cardinality;
    }
    
    /**
      * @notice Calculate token accumulation beween timestamp range.
      * @dev    Search the ring buffer for two checkpoint observations and diffs accumulator amount. 
      * @param _startTimestamp Account address 
      * @param _endTimestamp   Transfer amount
     */
    function getReserveAccumulatedBetween(uint32 _startTimestamp, uint32 _endTimestamp) external override view returns (uint224) {
        require(_startTimestamp < _endTimestamp, "Reserve/start-less-then-end");
        uint16 _cardinality = cardinality;

        ObservationLib.Observation memory _newestObservation;
        if (_cardinality > 0) {
            _newestObservation = reserveAccumulators[_cardinality - 1];
        }
        ObservationLib.Observation memory _oldestObservation = reserveAccumulators[0]; 

        uint224 _start = _getReserveAccumulatedAt(
            _newestObservation,
            _oldestObservation,
            _cardinality,
            _startTimestamp
        );

        uint224 _end = _getReserveAccumulatedAt(
            _newestObservation,
            _oldestObservation,
            _cardinality,
            _endTimestamp
        );

        return _end - _start;
    }

    /**
      * @notice Transfer Reserve token balance to recipient address.
      * @dev    Creates checkpoint before token transfer. Increments withdrawAccumulator with amount.
      * @param _recipient Account address 
      * @param _amount    Transfer amount
     */
    function withdrawTo(address _recipient, uint256 _amount) external override onlyManagerOrOwner {
        _checkpoint();

        token.safeTransfer(_recipient, _amount);
        withdrawAccumulator += uint224(_amount);
        
        emit Withdrawn(_recipient, _amount);
    }

    /* ============ Internal Functions ============ */

    /**
      * @notice Find optimal observation checkpoint using target timestamp
      * @dev    Uses binary search if target timestamp is within ring buffer range.
      * @param _newestObservation ObservationLib.Observation
      * @param _oldestObservation ObservationLib.Observation
      * @param _cardinality       RingBuffer Range
      * @param timestamp          Timestamp target
      *
      * @return Optimal reserveAccumlator for timestamp.
     */
    function _getReserveAccumulatedAt(
        ObservationLib.Observation memory _newestObservation,
        ObservationLib.Observation memory _oldestObservation,
        uint16 _cardinality,
        uint32 timestamp
    ) internal view returns (uint224) {
        uint32 timeNow = uint32(block.timestamp);

        // IF empty ring buffer exit early.
        if (_cardinality == 0) return 0;

        /**
          * Ring Buffer Search Optimization
          * Before performing binary search on the ring buffer check 
          * to see if timestamp is within range of [o T n] by comparing
          * the target timestamp to the oldest/newest observation.timestamps
          * IF the timestamp is out of the ring buffer range avoid starting
          * a binary search, because we can return NULL or oldestObservation.amount
        */

        /**
          * IF oldestObservation.timestamp is after timestamp: T[old ]
          * the Reserve did NOT have a balance or the ring buffer
          * no longer contains that timestamp checkpoint.
         */
        if(_oldestObservation.timestamp > timestamp) {
            return 0;
        }

        /**
          * IF newestObservation.timestamp is before timestamp: [ new]T
          * return _newestObservation.amount since observation is
          * contains the highest checkpointed reserveAccumulator.
         */
        if(_newestObservation.timestamp <= timestamp) {
            return _newestObservation.amount;
        }
        
        // IF the timestamp is witin range of ring buffer start/end: [new T old]
        // FIND the closest observation to the left(or exact) of timestamp: [OT ]
        (ObservationLib.Observation memory beforeOrAt, ObservationLib.Observation memory atOrAfter) = 
            ObservationLib.binarySearch(reserveAccumulators, _cardinality - 1, 0, timestamp, _cardinality, timeNow);
        
        // IF target timestamp is EXACT match for atOrAfter.timestamp observation return amount.
        // NOT having an exact match with atOrAfter means values will contain accumulator value AFTER the searchable range.
        if(atOrAfter.timestamp == timestamp) {
            return atOrAfter.amount;
        }

        // ELSE return observation.totalDepositedAccumlator closest to LEFT of target timestamp.
        else {
            return beforeOrAt.amount;      
        }
    }

    function _checkpoint() internal {
        uint256 _cardinality = cardinality;
        uint256 _balanceOfReserve = token.balanceOf(address(this));
        uint224 _withdrawAccumulator = withdrawAccumulator; //sload
        ObservationLib.Observation memory _newestObservation = _getNewestObservation(_cardinality);

        /**
          * IF tokens have been deposited into Reserve contract since the last checkpoint
          * create a new Reserve balance checkpoint. The will will update multiple times in a single block.
         */
        if(_balanceOfReserve + _withdrawAccumulator > _newestObservation.amount) {
            uint32 now = uint32(block.timestamp);
            
            // checkpointAccumulator = currentBalance + totalWithdraws
            uint224 newReserveAccumulator = uint224(_balanceOfReserve) + _withdrawAccumulator;
            
            // IF _newestObservation IS NOT in the current block.
            // CREATE observation in the accumulators ring buffer.
            if(_newestObservation.timestamp != now) {
                reserveAccumulators[_cardinality] = ObservationLib.Observation({
                    amount: newReserveAccumulator, 
                    timestamp: now
                });
                cardinality++;
            }
            // ELSE IF _newestObservation IS in the current block.
            // UPDATE the checkpoint previously created in block history.
            else {
                reserveAccumulators[_cardinality - 1] = ObservationLib.Observation({
                    amount: newReserveAccumulator, 
                    timestamp: now
                });
            }
            emit Checkpoint(newReserveAccumulator, _withdrawAccumulator);
        }        
    }   

    function _getNewestObservation(uint256 _cardinality) internal view returns (ObservationLib.Observation memory _observation) {
        if (_cardinality > 0) _observation = reserveAccumulators[_cardinality - 1]; 
    }


}