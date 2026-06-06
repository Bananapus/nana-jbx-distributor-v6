// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBActiveVotes} from "@bananapus/core-v6/src/interfaces/IJBActiveVotes.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @notice Mock JBX voting token exposing per-account votes and total active-vote checkpoints.
contract MockJBX is IJBActiveVotes, IVotes {
    /// @notice The current delegate for each account.
    /// @custom:param account The delegating account.
    mapping(address account => address delegatee) public override delegates;

    /// @notice The configured current active-vote total.
    uint256 public currentTotalActiveVotes;

    /// @notice The configured current votes for each account.
    /// @custom:param account The account whose current votes are being tracked.
    mapping(address account => uint256 votes) public currentVotesOf;

    /// @notice The configured historical active-vote total by block.
    /// @custom:param blockNumber The historical block being tracked.
    mapping(uint256 blockNumber => uint256 activeVotes) public pastTotalActiveVotesOf;

    /// @notice The configured historical votes by account and block.
    /// @custom:param account The account whose historical votes are being tracked.
    /// @custom:param blockNumber The historical block being tracked.
    mapping(address account => mapping(uint256 blockNumber => uint256 votes)) public pastVotesOf;

    /// @notice Ignore signed delegation in tests.
    /// @param delegatee The delegatee address.
    /// @param nonce The signature nonce.
    /// @param expiry The signature expiry.
    /// @param v The signature recovery byte.
    /// @param r The signature `r` value.
    /// @param s The signature `s` value.
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        pure
        override
    {
        delegatee;
        nonce;
        expiry;
        v;
        r;
        s;
    }

    /// @notice Delegate the caller's votes.
    /// @param delegatee The address receiving voting power.
    function delegate(address delegatee) external override {
        delegates[msg.sender] = delegatee;
    }

    /// @notice Get the historical votes configured for an account.
    /// @param account The account to query.
    /// @param timepoint The historical block to query.
    /// @return votes The configured historical votes.
    function getPastVotes(address account, uint256 timepoint) external view override returns (uint256 votes) {
        votes = pastVotesOf[account][timepoint];
    }

    /// @notice Get the historical total active votes configured for a block.
    /// @param blockNumber The historical block to query.
    /// @return activeVotes The configured active-vote total.
    function getPastTotalActiveVotes(uint256 blockNumber) external view override returns (uint256 activeVotes) {
        activeVotes = pastTotalActiveVotesOf[blockNumber];
    }

    /// @notice Get the historical total supply configured for a block.
    /// @param timepoint The historical block to query.
    /// @return totalSupply The configured active-vote total.
    function getPastTotalSupply(uint256 timepoint) external view override returns (uint256 totalSupply) {
        totalSupply = pastTotalActiveVotesOf[timepoint];
    }

    /// @notice Get the current active-vote total.
    /// @return activeVotes The configured current active-vote total.
    function getTotalActiveVotes() external view override returns (uint256 activeVotes) {
        activeVotes = currentTotalActiveVotes;
    }

    /// @notice Get the current votes configured for an account.
    /// @param account The account to query.
    /// @return votes The configured current votes.
    function getVotes(address account) external view override returns (uint256 votes) {
        votes = currentVotesOf[account];
    }

    /// @notice Set an account's current votes.
    /// @param account The account whose votes are being set.
    /// @param votes The votes to set.
    function setCurrentVotes(address account, uint256 votes) external {
        currentVotesOf[account] = votes;
    }

    /// @notice Set the current active-vote total.
    /// @param activeVotes The active-vote total to set.
    function setTotalActiveVotes(uint256 activeVotes) external {
        currentTotalActiveVotes = activeVotes;
    }

    /// @notice Set an account's historical votes.
    /// @param account The account whose historical votes are being set.
    /// @param blockNumber The historical block to set.
    /// @param votes The votes to set.
    function setPastVotes(address account, uint256 blockNumber, uint256 votes) external {
        pastVotesOf[account][blockNumber] = votes;
    }

    /// @notice Set the historical active-vote total for a block.
    /// @param blockNumber The historical block to set.
    /// @param activeVotes The active-vote total to set.
    function setPastTotalActiveVotes(uint256 blockNumber, uint256 activeVotes) external {
        pastTotalActiveVotesOf[blockNumber] = activeVotes;
    }
}
