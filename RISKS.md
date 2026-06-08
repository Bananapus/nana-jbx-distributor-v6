# Risks

## High Priority

### Incorrect JBX Address

`setJBX` is one-way. A wrong address permanently points rewards at the wrong checkpoint source. Deployments should set
JBX only after the target token address is verified on the destination chain.

### Split Hook Misconfiguration

Projects must send rewards through split hooks. Remote projects must send their project token, because suckers bridge by
cashing out project tokens into terminal tokens. A remote split that sends another ERC-20 or native ETH reverts.

### Sucker Registry Trust

Remote settlement trusts that the registered sucker belongs to the destination project and that its proof system
authenticates leaves correctly. `claimRemoteRewards` checks registry membership, leaf beneficiary, leaf metadata, and
leaf idempotency, but cannot repair an incorrectly registered sucker.

### Snapshot Timing

Each reward round uses the snapshot block recorded at first funding. Holders must be delegated before that block to
participate. Moving JBX into or out of custody before the snapshot changes eligibility for that round.

## Medium Priority

### Expiry Expectations

With nonzero `CLAIM_DURATION`, unmaterialized expired rewards can recycle. A staker who waits past the deadline can lose
access to that round if it is recycled before they begin vesting.

### Keeper Availability

Remote rewards need keepers to call `bridgeToMainnet` and `claimRemoteRewards`. Rewards remain safe in pending bridge
or sucker claim state, but stakers cannot claim them until keepers complete those steps.

### Fee-On-Transfer Tokens

Split funding records received balance deltas. Integrators should display accepted amounts, not sent amounts, for
fee-on-transfer reward tokens.

### Revnet Loan Complexity

Loan-backed vesting adds collateral locks, repayment, liquidation, and write-off state. Deployments that do not need
loans can set `revLoans` to the zero address.

## Low Priority

### Zero-Denominator Rounds

If a reward round records zero active JBX votes, no staker can claim it pro-rata. With a nonzero claim duration, that
inventory can recycle into a later active-voter round.

### Helper Collection Confusion

Permissionless helpers can collect only to the encoded holder. A helper cannot redirect another holder's rewards, but
frontends should label helper collection clearly so users understand where funds go.
