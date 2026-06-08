# Architecture

## Purpose

`nana-jbx-distributor-v6` routes rewards from Juicebox project splits to mainnet JBX stakers. It keeps the generic
round and vesting ledger from `JBDistributor`, but exposes a single production specialization: `JBXDistributor`.

## Modules

| Module | Responsibility |
| --- | --- |
| `JBXDistributor` | Authenticates split callers, queues remote project-token rewards, prepares sucker bridge leaves, settles mainnet sucker claims, and restricts all reward accounting to the configured JBX token. |
| `JBDistributor` | Records reward rounds, snapshots, vesting entries, collections, expiry recycling, and optional Revnet loan-backed vesting. |
| `IJBXDistributor` | Integration surface for split hooks, bridge keepers, and mainnet settlement keepers. |

## Local Mainnet Flow

```text
project split
  -> terminal/controller calls processSplitWith
  -> distributor pulls or receives the split amount
  -> current round records the reward token, amount, snapshot block, claim deadline, and JBX active-vote total
  -> staker or helper begins vesting after the round completes
  -> vested rewards are collected to the encoded holder address unless the holder redirects them
```

## Remote Flow

```text
remote project split
  -> terminal/controller calls processSplitWith with the project token
  -> distributor queues pendingBridgeAmountOf[projectId][projectToken]
  -> keeper calls bridgeToMainnet with a registered sucker that peers to mainnet
  -> sucker prepare writes a leaf whose beneficiary is this distributor and whose metadata identifies origin chain/project
  -> mainnet keeper calls claimRemoteRewards with the origin project ID, mainnet project ID, and sucker proof
  -> claimed destination project tokens enter the current mainnet JBX reward round
```

## JBX Setup

`setJBX` is owner-only and one-way. The zero address is rejected, and any later attempt to replace the token reverts.
Funding and settlement paths that would write reward rounds require JBX to be set first on mainnet.

## Eligibility

Only active JBX voting power shares rewards. A holder is active when their JBX voting units are delegated to a nonzero
delegate at the funded round's snapshot block. The delegate does not receive rewards; the encoded holder address does.

## Trust Boundaries

- `JBDirectory` decides whether `processSplitWith` was called by a project terminal or controller.
- `IJBTokens` decides the project token used for remote bridge queues and mainnet destination reward tokens.
- `IJBSuckerRegistry` decides whether a sucker belongs to a project.
- The sucker proof authenticates bridged leaf contents.
- JBX checkpoint history provides holder votes and total active votes.

## Inventory Accounting

Reward tokens remain in the distributor while they are unclaimed, vesting, or collateralized in a distributor-held
Revnet loan. `_balanceOf` and `_accountedBalanceOf` track custody so collections, recycle paths, and loan paths cannot
spend the same inventory twice.
