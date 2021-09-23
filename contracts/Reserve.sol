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

    ObservationLib.Observation[65535] public reserveAccumulators;

    uint16 public cardinality;
    
    /* ============ Events ============ */

    event Deployed(IERC20 indexed token);

    /* ============ Constructor ============ */
    
    constructor(address _owner, IERC20 _token) Ownable(_owner) {
        token = _token;
        emit Deployed(_token);
    }

    /* ============ External Functions ============ */

    function withdrawTo(address _recipient, uint256 _amount) external override onlyManagerOrOwner {
        _checkpoint();

        token.safeTransfer(_recipient, _amount);
        withdrawAccumulator += uint224(_amount);
        
        emit Withdrawn(_recipient, _amount);
    }
    
    function checkpoint() external override {
        _checkpoint();
    }    
    
    function getReserveAccumulatedBetween(uint32 _startTimestamp, uint32 _endTimestamp) external override view returns (uint224) {
        require(_startTimestamp < _endTimestamp, "Reserve/start-less-then-end");
        uint32 timeNow = uint32(block.timestamp);
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

        // cases where we have observations between startTimestamp and endTimestamp
        return _end - _start;
    }

    function getCardinality() external view returns (uint16) {
        return cardinality;
    }

    function _getReserveAccumulatedAt(
        ObservationLib.Observation memory _newestObservation,
        ObservationLib.Observation memory _oldestObservation,
        uint16 _cardinality,
        uint32 timestamp
    ) internal view returns (uint224) {
        uint32 timeNow = uint32(block.timestamp);
        if (_cardinality == 0) {
            return 0;
        }

        if(_oldestObservation.timestamp > timestamp) {
            return 0;
        }

        if(_newestObservation.timestamp <= timestamp) {
            return _newestObservation.amount;
        }
        
        (ObservationLib.Observation memory beforeOrAt, ObservationLib.Observation memory atOrAfter) = 
            ObservationLib.binarySearch(reserveAccumulators, _cardinality - 1, 0, timestamp, _cardinality, timeNow);
        
        if(atOrAfter.timestamp == timestamp) {
            return atOrAfter.amount;
        }
        else {
            return beforeOrAt.amount;      
        }
    }

    /* ============ Internal Functions ============ */
    function _checkpoint() internal {
        uint256 balanceOfReserve = token.balanceOf(address(this));
        uint224 _withdrawAccumulator = withdrawAccumulator; //sload

        ObservationLib.Observation memory _reserveAccumulators;

        uint256 _cardinality = cardinality;

        if (_cardinality > 0) {
            _reserveAccumulators = reserveAccumulators[_cardinality - 1]; 
        }

        if(balanceOfReserve + _withdrawAccumulator > _reserveAccumulators.amount) {
            
            uint32 now = uint32(block.timestamp);
            uint224 newReserveAccumulator = uint224(balanceOfReserve) + _withdrawAccumulator;
            
            if(_reserveAccumulators.timestamp != now) {
                // store next observation
                reserveAccumulators[_cardinality] = ObservationLib.Observation({
                    amount: newReserveAccumulator, 
                    timestamp: now
                });
                cardinality++;
            }
            else {
                reserveAccumulators[_cardinality - 1] = ObservationLib.Observation({
                    amount: newReserveAccumulator, 
                    timestamp: now
                });
            }
            emit Checkpoint(newReserveAccumulator, _withdrawAccumulator);
        }        
    }   


}