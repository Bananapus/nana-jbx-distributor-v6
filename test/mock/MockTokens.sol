// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBToken} from "@bananapus/core-v6/src/interfaces/IJBToken.sol";

/// @notice Minimal token registry mock for project-token lookups.
contract MockTokens {
    /// @notice The project ID registered for each token.
    /// @custom:param token The token whose project ID is being tracked.
    mapping(IJBToken token => uint256 projectId) public projectIdOf;

    /// @notice The token registered for each project.
    /// @custom:param projectId The project whose token is being tracked.
    mapping(uint256 projectId => IJBToken token) public tokenOf;

    /// @notice Register a project token.
    /// @param projectId The project whose token is being set.
    /// @param token The token to register.
    function setTokenFor(uint256 projectId, IJBToken token) external {
        tokenOf[projectId] = token;
        projectIdOf[token] = projectId;
    }
}
