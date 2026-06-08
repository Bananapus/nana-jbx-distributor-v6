# Juicebox JBX Distributor

`@bananapus/jbx-distributor-v6` distributes split-funded rewards to mainnet JBX stakers. Rewards are shared by JBX
holders with nonzero delegated voting power at each reward round's snapshot block, then vest linearly before they are
collected.

The package is intentionally narrow:

- projects submit rewards through Juicebox split hooks
- same-chain mainnet splits fund JBX reward rounds directly
- remote-chain project-token splits queue for a sucker bridge to mainnet
- mainnet sucker claims settle bridged project tokens into the same JBX reward ledger
- the admin sets the JBX staking token once, and cannot replace it

## Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - module overview, cross-chain flow, and trust boundaries.
- [USER_JOURNEYS.md](./USER_JOURNEYS.md) - end-to-end flows for projects, keepers, and JBX stakers.
- [INVARIANTS.md](./INVARIANTS.md) - properties the reward ledger, vesting math, and bridge settlement must preserve.
- [RISKS.md](./RISKS.md) - operational and integration risks.
- [ADMINISTRATION.md](./ADMINISTRATION.md) - deployment parameters and one-time admin action.
- [references/operations.md](./references/operations.md) - operator checklist.
- [references/runtime.md](./references/runtime.md) - runtime behavior notes.

## Contracts

| Contract | Role |
| --- | --- |
| `JBXDistributor` | Split hook, remote bridge queue, mainnet sucker settlement, and JBX reward specialization. |
| `JBDistributor` | Shared round, vesting, collection, expiry, and optional Revnet vesting-loan accounting. |
| `IJBXDistributor` | Integration interface for split-hook funding, bridge preparation, settlement, and JBX setup. |

## Reward Model

Each funded round records:

- the accepted reward token and amount
- a snapshot block fixed at first funding for that round
- `IJBActiveVotes.getPastTotalActiveVotes(snapshotBlock)` as the denominator
- the configured claim deadline, if `CLAIM_DURATION != 0`

Each staker's numerator is `IVotes(JBX).getPastVotes(staker, snapshotBlock)`. The delegate address determines whether
the holder has active voting power, but rewards belong to the encoded holder address. Helpers can begin vesting or
collect to that canonical holder, so stakers do not need to submit every reward-cycle transaction themselves.

## Cross-Chain Model

Remote chains do not distribute directly. A remote project's split sends that project's token to `JBXDistributor` on
the remote chain. A keeper calls `bridgeToMainnet`, which prepares a sucker leaf with this distributor as the mainnet
beneficiary and metadata identifying the origin chain and project. On mainnet, `claimRemoteRewards` authenticates the
leaf and records the destination project tokens as JBX rewards.

## Install

```bash
npm install @bananapus/jbx-distributor-v6
```

## Development

```bash
npm install
forge test --deny notes --fail-fast --summary --detailed --skip "*/script/**"
forge fmt --check
```
