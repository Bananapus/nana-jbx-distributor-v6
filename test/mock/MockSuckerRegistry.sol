// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal sucker registry mock for registered-sucker authorization.
contract MockSuckerRegistry {
    /// @notice Whether an address is registered as a sucker for a project.
    /// @custom:param projectId The project whose sucker is being tracked.
    /// @custom:param addr The sucker address to check.
    mapping(uint256 projectId => mapping(address addr => bool isSucker)) public isSuckerOf;

    /// @notice Set whether an address is registered as a sucker for a project.
    /// @param projectId The project whose sucker is being set.
    /// @param addr The sucker address to set.
    /// @param isSucker Whether `addr` should be treated as a sucker.
    function setIsSuckerOf(uint256 projectId, address addr, bool isSucker) external {
        isSuckerOf[projectId][addr] = isSucker;
    }
}
