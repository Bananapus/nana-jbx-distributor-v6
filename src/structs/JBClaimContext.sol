// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Parameters describing one lazy claim of completed reward rounds into a fresh vesting entry.
/// @custom:member hook The stake source whose historical rewards are being claimed.
/// @custom:member groupId The reward group being claimed (0 = the default group).
/// @custom:member lastClaimableRound The last completed reward round included in the claim.
/// @custom:member vestingReleaseRound The round at which newly materialized rewards finish vesting.
struct JBClaimContext {
    address hook;
    uint256 groupId;
    uint256 lastClaimableRound;
    uint256 vestingReleaseRound;
}
