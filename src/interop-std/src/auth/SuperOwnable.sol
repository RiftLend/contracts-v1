// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {Ownable} from "@solady/auth/Ownable.sol";
import {Predeploys} from "../../../libraries/Predeploys.sol";

import {ISemver} from "../../../interfaces/ISemver.sol";
import {Identifier, ICrossL2Inbox} from "../../../interfaces/ICrossL2Inbox.sol";

abstract contract SuperOwnable is Ownable, ISemver {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error IdOriginNotSuperOwnable();
    error DataNotCrosschainOwnershipTransfer();
    error DataNotCrosschainSuperAdminChainIdUpdate();
    error OwnershipNotInSync();
    error NoOwnershipChange();
    error NotSuperAdmin();
    error ChainNotSuperAdmin();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event InitiateCrosschainOwnershipTransfer(address indexed previousOwner, address indexed newOwner);
    event CrosschainOwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SuperAdminChainIdUpdated(uint64 indexed superAdminChainId);
    event InitiateCrosschainSuperAdminChainIdUpdate(
        uint64 indexed superAdminChainId, uint64 indexed newSuperAdminChainId
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STATE VARIABLES                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint64 superAdminChainId;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           MODIFIERS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlySuperAdmin() {
        if (!(msg.sender == owner() && block.chainid == superAdminChainId)) revert NotSuperAdmin();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        EXTERNAL FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta.1
    function version() external view virtual returns (string memory) {
        return "1.0.0-beta.1";
    }

    function _setSuperAdminChainId(uint64 newSuperAdminChainId) internal virtual {
        superAdminChainId = newSuperAdminChainId;
        emit SuperAdminChainIdUpdated(superAdminChainId);
    }

    function updateCrosschainSuperAdminChainId(Identifier calldata _identifier, bytes calldata _data)
        external
        virtual
    {
        if (_identifier.origin != address(this)) revert IdOriginNotSuperOwnable();
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_identifier, keccak256(_data));

        // Decode `InitiateCrosschainSuperAdminChainIdUpdate` event
        bytes32 selector = abi.decode(_data[:32], (bytes32));
        if (selector != InitiateCrosschainSuperAdminChainIdUpdate.selector) {
            revert DataNotCrosschainSuperAdminChainIdUpdate();
        }

        (uint64 newSuperAdminChainId) = abi.decode(_data[32:], (uint64));
        _setSuperAdminChainId(newSuperAdminChainId);
    }

    function updateSuperAdminChainId(uint64 newSuperAdminChainId) external virtual onlyOwner {
        if (block.chainid != superAdminChainId) revert ChainNotSuperAdmin();
        _setSuperAdminChainId(newSuperAdminChainId);
        emit InitiateCrosschainSuperAdminChainIdUpdate(superAdminChainId, newSuperAdminChainId);
    }

    /**
     * @notice Updates the owner of the contract.
     * @param _identifier The identifier of the cross-chain message.
     * @param _data The data of the cross-chain message.
     */
    function updateCrosschainOwner(Identifier calldata _identifier, bytes calldata _data) external virtual {
        if (_identifier.origin != address(this)) revert IdOriginNotSuperOwnable();
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_identifier, keccak256(_data));

        // Decode `CrosschainOwnershipTransfer` event
        bytes32 selector = abi.decode(_data[:32], (bytes32));
        if (selector != InitiateCrosschainOwnershipTransfer.selector) revert DataNotCrosschainOwnershipTransfer();
        (address previousOwner, address newOwner) = abi.decode(_data[32:], (address, address));
        if (previousOwner != owner()) revert OwnershipNotInSync();
        if (newOwner == owner()) revert NoOwnershipChange();

        _setOwner(newOwner);

        emit CrosschainOwnershipTransferred(previousOwner, newOwner);
    }

    function transferOwnership(address newOwner) public payable virtual override onlySuperAdmin {
        super.transferOwnership(newOwner);
    }

    function renounceOwnership() public payable virtual override onlySuperAdmin {
        super.renounceOwnership();
    }

    function completeOwnershipHandover(address pendingOwner) public payable virtual override onlySuperAdmin {
        super.completeOwnershipHandover(pendingOwner);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        INTERNAL FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * emits an extra event to notify the cross-chain contract of the ownership change.
     * Internal function without access restriction.
     */
    function _setOwner(address newOwner) internal virtual override {
        emit InitiateCrosschainOwnershipTransfer(owner(), newOwner);
        super._setOwner(newOwner);
    }

    function _initializeSuperOwner(uint64 newSuperAdminchainId, address newOwner) internal virtual {
        _setOwner(newOwner);
        _setSuperAdminChainId(newSuperAdminchainId);
    }
}
