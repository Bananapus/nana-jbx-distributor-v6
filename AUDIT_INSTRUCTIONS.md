# Audit Instructions

## Scope

Primary scope:

- `src/JBXDistributor.sol`
- `src/JBDistributor.sol`
- `src/interfaces/IJBXDistributor.sol`
- `src/interfaces/IJBDistributor.sol`
- `src/libraries/JBVestingMath.sol`
- `src/structs/*.sol`

Test reference:

- `test/JBXDistributor.t.sol`

## System Statement

The distributor accepts project split rewards, records them against JBX active-vote snapshots, and lets holders or
helpers begin vesting and collect unlocked rewards. Remote rewards move through project suckers before becoming mainnet
JBX rewards.

## Focus Areas

- one-time JBX setup and hook restriction
- split-hook caller authorization
- remote project-token-only queueing
- sucker registration, peer-chain, state, beneficiary, metadata, and leaf idempotency checks
- active-vote denominator and holder-vote numerator consistency
- permissionless helper collection routing to canonical holders
- expiry recycling preserving already materialized rewards
- balance accounting across reward rounds, vesting, recycling, and optional Revnet loans

## Out Of Scope

- project ruleset configuration correctness
- sucker root relay liveness
- JBX checkpoint implementation correctness
- Revnet loan economic parameters outside this distributor's collateral accounting
