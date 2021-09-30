// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

library GasLib {
    struct Tracker {
        uint256 startingGas;
        uint256 deltaGas;
    }

    function init(Tracker memory tracker) internal view returns (Tracker memory) {
        tracker.startingGas = gasleft();
        tracker.deltaGas = gasleft();

        return tracker;
    }

    function mark(Tracker memory tracker, string memory message)
        internal
        view
        returns (Tracker memory)
    {
        uint256 diff = tracker.deltaGas - gasleft();
        tracker.deltaGas = gasleft();

        return tracker;
    }

    function done(Tracker memory tracker, string memory message) internal view {
        uint256 diff = tracker.startingGas - gasleft();
    }
}
