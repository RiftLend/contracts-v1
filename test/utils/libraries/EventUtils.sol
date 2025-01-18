import "forge-std/Vm.sol";

pragma solidity 0.8.25;

library EventUtils {
    /**
     * @notice Utility function to locate specific events in the event logs
     * @param entries Array of event logs to search
     * @param _selector Event selector to find
     */
    function findEventsBySelector(Vm.Log[] memory entries, bytes32 _selector) public pure returns (bytes[] memory) {
        uint256 numEvents = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == _selector) {
                numEvents++;
            }
        }
        bytes[] memory events = new bytes[](numEvents);
        uint256 idx = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == _selector) {
                events[idx++] = (entries[i].data); // entries[i].data;
            }
        }
        return events;
    }
}
