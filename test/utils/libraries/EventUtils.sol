import "forge-std/Vm.sol";
pragma solidity 0.8.25;

library EventUtils {
    /**
     * @notice Utility function to locate specific events in the event logs
     * @param entries Array of event logs to search
     * @param _selector Event selector to find
     * @return bytes The event data if found, empty bytes if not found
     */
    function findEventBySelector(Vm.Log[] memory entries, bytes32 _selector) public pure returns (bytes memory) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == _selector) {
                return entries[i].data;
            }
        }
        return bytes("");
    }
}
