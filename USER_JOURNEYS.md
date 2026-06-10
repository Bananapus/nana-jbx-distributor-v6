# User Journeys

## 1. Admin Sets JBX

The protocol admin deploys `JBXDistributor` with the round duration, vesting rounds, claim duration, directory, token
registry, sucker registry, and mainnet chain ID. After deployment, the admin calls `setJBX(jbx)`.

Outcome:

- JBX is the only staking token whose active voters can receive rewards.
- The JBX address cannot be changed.
- Mainnet funding and settlement can begin.

## 2. Mainnet Project Funds JBX Rewards

A mainnet Juicebox project adds `JBXDistributor` as a split hook. During payout or reserved-token distribution, the
terminal or controller calls `processSplitWith`.

Outcome:

- native ETH or ERC-20 reward tokens are accepted on mainnet
- the current reward round records a snapshot block and total active JBX votes
- only JBX holders with `getPastVotes(holder, snapshotBlock) > 0` share the round

## 3. Remote Project Sends Rewards To Mainnet JBX

A remote project adds `JBXDistributor` as a split hook for its project token. The remote terminal or controller calls
`processSplitWith`, and the distributor queues the project token for bridging.

A keeper then calls `bridgeToMainnet(projectId, sucker, terminalToken, amount, minTokensReclaimed)`.

Outcome:

- remote rewards cannot distribute locally
- the registered sucker prepares a mainnet leaf for this distributor
- the leaf metadata binds the origin chain and project ID

## 4. Mainnet Keeper Settles Remote Rewards

After the sucker root reaches mainnet, any caller submits `claimRemoteRewards(originChainId, projectId, sucker,
claimData)`.

Outcome:

- the leaf beneficiary must be this distributor
- the leaf metadata must match the claimed origin chain and project
- each sucker leaf can settle once
- destination project tokens are recorded into the current JBX reward round

## 5. Holder Opts Into JBX Rewards

A JBX holder delegates to any nonzero address. Self-delegation works. The delegated address controls voting power, but
does not receive reward payouts.

Outcome:

- the holder's delegated voting units count in active-vote totals
- if the holder moves JBX away before a reward snapshot, that moved balance is not eligible for that snapshot
- when the holder receives JBX back, the returned balance participates automatically while still delegated

## 6. Helper Begins Vesting For A Holder

After at least one later reward round starts, any caller can call `beginVesting(tokenIds, tokens)`. Each `tokenId` is
the holder address encoded as `uint256(uint160(holder))`.

Outcome:

- no tokens leave the distributor
- completed unclaimed rounds are materialized into a vesting entry for the holder
- zero-vote holders advance through empty claims without consuming reward inventory

## 7. Holder Or Helper Collects Vested Rewards

Any caller can call `collectVestedRewards(address(JBX), tokenIds, tokens, holder)` to collect unlocked rewards to the
canonical holder. A holder can also collect to another beneficiary for token IDs they control.

Outcome:

- helpers can do the gas work without redirecting funds
- the delegate address receives nothing unless it is also the holder or chosen beneficiary
- rewards unlock linearly across `VESTING_ROUNDS`

## 8. Expired Inventory Recycles

If `CLAIM_DURATION` is nonzero, any caller can recycle expired reward rounds with `recycleExpiredRewards`. Only the
unmaterialized remainder of an expired round is recycled. A zero-active prior round can also recycle because it has no
possible claimant, but the current round never recycles into itself.

Outcome:

- rewards that started vesting are preserved
- rewards that did not start vesting enter a later active-voter round
- deployments with `CLAIM_DURATION == 0` keep reward rounds non-expiring
