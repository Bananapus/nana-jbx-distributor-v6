// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Minimal directory mock for split-hook caller authorization tests.
contract MockDirectory {
    /// @notice The controller registered for each project.
    /// @custom:param projectId The project whose controller is being tracked.
    mapping(uint256 projectId => IERC165 controller) public controllerOf;

    /// @notice Whether an address is a terminal for a project.
    /// @custom:param projectId The project whose terminal is being tracked.
    /// @custom:param terminal The terminal address to check.
    mapping(uint256 projectId => mapping(IJBTerminal terminal => bool isTerminal)) public isTerminalOf;

    /// @notice Set a project's controller.
    /// @param projectId The project whose controller is being set.
    /// @param controller The controller to register.
    function setControllerOf(uint256 projectId, IERC165 controller) external {
        controllerOf[projectId] = controller;
    }

    /// @notice Set whether an address is a project terminal.
    /// @param projectId The project whose terminal permission is being set.
    /// @param terminal The terminal to update.
    /// @param isTerminal Whether the address should be treated as a terminal.
    function setIsTerminalOf(uint256 projectId, IJBTerminal terminal, bool isTerminal) external {
        isTerminalOf[projectId][terminal] = isTerminal;
    }
}
