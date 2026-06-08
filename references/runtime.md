# Runtime Notes

## Snapshots

Funding records `block.number - 1` the first time a reward token enters a round. JBX holder votes and total active
votes are both read from that block.

## Delegation

The holder must have votes at the snapshot block. Delegation can be to any nonzero address, including the holder
itself. Rewards vest and collect for the holder address encoded in `tokenId`.

## Split Tokens

Mainnet splits can fund native ETH or ERC-20 reward tokens. Remote splits must fund project tokens so suckers can move
the value to mainnet.

## Sucker Metadata

`packLeafMetadata(originChainId, projectId)` packs the origin chain into bits `[95:64]` and the project ID into bits
`[63:0]`. Settlement rejects leaves whose metadata does not match the claimed origin.

## Claim Deadlines

`CLAIM_DURATION == 0` means rounds do not expire. Nonzero claim duration creates a fixed deadline for each funded round.
After the deadline, unmaterialized inventory can recycle into the current JBX reward round.
