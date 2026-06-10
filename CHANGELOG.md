# Changelog

## 0.0.4

### Fixed

- `JBDistributor._recycleExpiredRewardRound` now treats same-round recycle requests as no-ops. Zero-active reward
  rounds still recycle once a later round is current, but they cannot recycle into themselves and inflate raw
  `rewardRoundOf.amount` or `claimedAmount` fields for off-chain indexers.

## 0.0.3

### Fixed

- `JBDistributor._recycleExpiredRewardRound` now recycles a reward round whose snapshot `totalStake` is zero
  regardless of its claim deadline. Such a round can never be claimed; gating recycling on expiry stranded its funds
  permanently under a never-expiring (`CLAIM_DURATION == 0`) configuration. Live, staked, unexpired rounds are
  unaffected.

## 0.0.1

Initial JBX distributor package.

### Added

- `JBXDistributor`, a split-hook reward distributor for mainnet JBX active voters.
- One-time `setJBX` admin setup.
- Mainnet split funding for native ETH and ERC-20 reward tokens.
- Remote project-token split queues.
- `bridgeToMainnet` for registered sucker bridge preparation.
- `claimRemoteRewards` for mainnet sucker leaf settlement.
- Permissionless begin-vesting and canonical-beneficiary collection.
- Expired reward recycling into the current JBX active-voter round.
- Shared linear vesting and optional Revnet loan-backed vesting through `JBDistributor`.

### Package

- Package name: `@bananapus/jbx-distributor-v6`
- Version: `0.0.1`
