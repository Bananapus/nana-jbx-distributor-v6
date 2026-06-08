# Changelog

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
