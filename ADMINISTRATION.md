# Administration

## Deployment Parameters

| Parameter | Meaning |
| --- | --- |
| `directory` | Verifies terminal/controller split-hook callers. |
| `controller` | Used by the shared vesting-loan path for Revnet token/project checks. |
| `tokens` | Resolves project tokens for remote bridge queues and mainnet settlement. |
| `suckerRegistry` | Verifies registered project suckers. |
| `revLoans` | Optional Revnet loans contract; use zero address to disable loan-backed vesting. |
| `revOwner` | Revnet owner expected to own reward-token projects for loan-backed vesting. |
| `owner` | Admin that can set JBX once. |
| `mainnetChainId` | Chain ID where JBX rewards are distributed. |
| `initialRoundDuration` | Seconds per reward/vesting round; cannot be zero. |
| `initialVestingRounds` | Number of rounds until newly claimed rewards fully vest. |
| `initialClaimDuration` | Seconds after a reward round becomes claimable before unmaterialized inventory can expire. |

## One-Time Action

After deployment, the owner calls `setJBX(jbx)`.

Checklist:

- verify the JBX token address
- verify the token exposes `IVotes.getPastVotes`
- verify the token exposes `IJBActiveVotes.getPastTotalActiveVotes`
- call `setJBX`
- verify later `setJBX` calls revert

## Project Configuration

Projects fund rewards by adding `JBXDistributor` as a split hook.

Mainnet projects can send native ETH or ERC-20 reward tokens. Remote projects must send their own project token so a
keeper can call `bridgeToMainnet` through that project's sucker.

## Keeper Operations

Remote keepers:

- watch `pendingBridgeAmountOf(projectId, projectToken)`
- choose a registered sucker that peers to mainnet
- call `bridgeToMainnet`
- relay/send sucker roots as required by sucker infrastructure

Mainnet keepers:

- wait until the sucker proof is available
- call `claimRemoteRewards`
- call `beginVesting` for holders when useful
- call `collectVestedRewards` to canonical holders when useful
- call `recycleExpiredRewards` after claim deadlines

## No Runtime Admin Controls

The admin cannot change JBX after setup, cannot pause rewards, cannot change durations, and cannot redirect reward
inventory. Runtime behavior is controlled by split configuration, keeper calls, sucker settlement, and holder
delegation state.
