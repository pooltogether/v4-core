// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

interface IGaugeController {
    /**
     * @notice Get the gauge scaled average balance between two timestamps.
     * @param _gauge Address of the gauge to get the average scaled balance for
     * @param _startTime Start timestamp at which to get the average scaled balance
     * @param _endTime End timestamp at which to get the average scaled balance
     * @return The gauge scaled average balance between the two timestamps
     */
    function getScaledAverageGaugeBalanceBetween(
        address _gauge,
        uint256 _startTime,
        uint256 _endTime
    ) external view returns (uint256);
    
    /**
     * @notice Read Gauge balance.
     * @param _gauge Address of existing Gauge
     * @return uint256 GaugeTWAB.details.balance
     */
     function getGaugeBalance(address _gauge) external view returns (uint256);

     /**
      * @notice Read Gauge scaled balance.
      * @param _gauge Address of existing Gauge
      * @return uint256 GaugeScaleTWAB.details.balance
      */
     function getGaugeScaleBalance(address _gauge) external view returns (uint256);
 
     /**
      * @notice Get the user stake balance for a given gauge
      * @param _gauge Address of the gauge to get stake balance for
      * @param _user Address of the user to get stake balance for
      * @return The user gauge balance
      */
     function getUserGaugeBalance(address _gauge, address _user) external view returns (uint256);
}