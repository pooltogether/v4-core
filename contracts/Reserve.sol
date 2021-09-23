// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./interfaces/IReserve.sol";
import "./libraries/ObservationLib.sol";
import "./libraries/RingBuffer.sol";

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "hardhat/console.sol";

contract Reserve is IReserve, Manageable {

    using SafeERC20 for IERC20;
    
    
    IERC20 public immutable token;

    uint224 public withdrawAccumulator;

    ObservationLib.Observation[65535] public reserveAccumulator;

    uint16 public reserveAccumulatorCardinality;
    

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
        withdrawAccumulator += uint224(amount);
        

    }
    
    function checkpoint() external override {
        _checkpoint();
    }    
    
    function getReserveAccumulatedBetween(uint32 startTimestamp, uint32 endTimestamp) external override view returns (uint224) {
        require(startTimestamp < endTimestamp, "Reserve/start-less-then-end");
        uint32 timeNow = uint32(block.timestamp);
        uint16 _reserveAccumulatorCardinality = reserveAccumulatorCardinality;

        uint224 _start =_getReserveAccumulatedAt(startTimestamp);
        console.log("getReserveAccumulatedBetween::_start ", _start);
        uint224 _end = _getReserveAccumulatedAt(endTimestamp);
        console.log("getReserveAccumulatedBetween::_end ", _end);

        // cases where we have observations between startTimestamp and endTimestamp
        return _end - _start;
    }

    function _getReserveAccumulatedAt(uint32 timestamp) internal view returns (uint224) {
        uint32 timeNow = uint32(block.timestamp);
        uint16 _reserveAccumulatorCardinality = reserveAccumulatorCardinality;
        if (_reserveAccumulatorCardinality == 0) {
            return 0;
        }

        ObservationLib.Observation memory _reserveAccumulatorNewest = reserveAccumulator[_reserveAccumulatorCardinality - 1];    
        ObservationLib.Observation memory _reserveAccumulator = reserveAccumulator[0];    

        if(_reserveAccumulator.timestamp > timestamp) {
            return 0;
        }

        if(_reserveAccumulatorNewest.timestamp <= timestamp) {
            return _reserveAccumulatorNewest.amount;
        }
        
        (ObservationLib.Observation memory beforeOrAt, ObservationLib.Observation memory atOrAfter) = 
            ObservationLib.binarySearch(reserveAccumulator, _reserveAccumulatorCardinality - 1, 0, timestamp, _reserveAccumulatorCardinality, timeNow);
        
        if(atOrAfter.timestamp == timestamp){
            return atOrAfter.amount;
        }
        else {
            return beforeOrAt.amount;      
        }
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

        console.log("balanceOfReserve", balanceOfReserve);
        console.log("_withdrawAccumulator", _withdrawAccumulator);
        console.log("_reserveAccumulator.amount", _reserveAccumulator.amount);
        if(balanceOfReserve + _withdrawAccumulator > _reserveAccumulator.amount){
            
            uint32 now = uint32(block.timestamp);
            uint224 newReserveAccumulator = uint224(balanceOfReserve) + _withdrawAccumulator;
            
            if(_reserveAccumulator.timestamp != now){
                // store next observation
                reserveAccumulator[_reserveAccumulatorCardinality] = ObservationLib.Observation({
                    amount: newReserveAccumulator, 
                    timestamp: now
                });
                reserveAccumulatorCardinality++;
            }
            else {
                reserveAccumulator[_reserveAccumulatorCardinality - 1] = ObservationLib.Observation({
                    amount: newReserveAccumulator, 
                    timestamp: now
                });
            }
            emit Checkpoint(newReserveAccumulator, _withdrawAccumulator);
        }        
    }   


}