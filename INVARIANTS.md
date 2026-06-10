# Invariants

## JBX Configuration

- `JBX` is unset until `setJBX` succeeds.
- `setJBX` rejects the zero address.
- `setJBX` succeeds at most once.
- All hook-keyed inherited entry points revert unless `hook == address(JBX)`.
- Direct `fund` always reverts; rewards enter through split hooks or mainnet sucker settlement.

## Split Funding

- `processSplitWith` accepts calls only from a terminal or controller registered in `JBDirectory`.
- On mainnet, accepted native ETH and ERC-20 balance deltas become current-round JBX rewards.
- On remote chains, accepted splits must use the project's project token.
- Remote accepted project tokens increase `pendingBridgeAmountOf[projectId][projectToken]`.
- Fee-on-transfer ERC-20 splits are credited by received balance delta, not by requested transfer amount.

## Remote Bridge Queue

- `bridgeToMainnet` is remote-chain only.
- The sucker must be registered for the project, belong to the same project ID, peer to mainnet, and be sending-enabled.
- The bridged amount cannot exceed the pending amount.
- Pending accounting is decremented before calling the sucker.
- The sucker allowance is set only for the prepared amount and cleared after `prepare`.
- The prepared leaf beneficiary is this distributor encoded as `bytes32`.
- The prepared leaf metadata is `packLeafMetadata(originChainId, projectId)`.

## Mainnet Settlement

- `claimRemoteRewards` is mainnet-only.
- The origin chain ID must be nonzero and different from mainnet.
- The sucker must be registered for the mainnet destination project.
- The sucker must report the mainnet destination project ID and the origin chain ID as its peer chain.
- The claimed leaf beneficiary must be this distributor.
- The claimed leaf metadata must match the asserted origin chain and origin project.
- A leaf identified by `(sucker, terminalToken, leafIndex)` can settle only once.
- If a sucker leaf was already claimed, its stored hash must match the provided leaf contents.
- The destination project token resolved from `IJBTokens.tokenOf(mainnetProjectId)` is the reward token recorded for JBX.

## Reward Rounds

- First funding in a round fixes the round's snapshot block.
- Subsequent funding in the same round increases the amount without changing the snapshot block or denominator.
- The denominator is `IJBActiveVotes(JBX).getPastTotalActiveVotes(snapshotBlock)`.
- A holder's numerator is `IVotes(JBX).getPastVotes(holder, snapshotBlock)`.
- Delegates affect active votes, but rewards remain assigned to the encoded holder address.

## Vesting And Collection

- `beginVesting` is permissionless and transfers no reward tokens.
- `collectVestedRewards` can be called by helpers only when the beneficiary is the encoded holder.
- Holders can redirect their own collected rewards.
- Vesting entries are append-only.
- `latestVestedIndexOf` only advances over exhausted entries.
- `totalVestingAmountOf` decreases only by amounts actually unlocked or written off.

## Expiry Recycling

- `CLAIM_DURATION == 0` makes reward rounds non-expiring.
- Nonzero claim duration gives each funded round one fixed deadline.
- Expiry recycling moves only `amount - claimedAmount`.
- Recycling preserves rewards that already started vesting.
- Recycled inventory is recorded into a later current JBX active-voter round.
- Passing the current round is a no-op, including for zero-stake rounds that can never be claimed.

## Revnet Vesting Loans

- Vesting loans are disabled when `VESTING_ROUNDS == 0`.
- A loan can collateralize one encoded holder and one reward token at a time.
- Loan collateral stays locked until repayment or write-off.
- Repayment restores collateral to the original vesting schedule.
- Liquidation write-off forfeits only the collateralized vesting entries.
