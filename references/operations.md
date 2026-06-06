# Operations

## Deployment

1. Deploy `JBXDistributor` on mainnet and any remote chain that will receive project splits.
2. Verify `MAINNET_CHAIN_ID`, `DIRECTORY`, `TOKENS`, and `SUCKER_REGISTRY`.
3. On mainnet, call `setJBX(jbx)` once.
4. Configure project splits to use the distributor as the split hook.

## Remote Rewards

1. Confirm the remote split sends the project's project token.
2. Watch `pendingBridgeAmountOf(projectId, projectToken)`.
3. Call `bridgeToMainnet` with a registered sucker that peers to mainnet.
4. Relay sucker roots using the project's sucker operations.
5. On mainnet, call `claimRemoteRewards` with the authenticated claim data.

## Staker Support

1. Confirm the holder delegated JBX before the reward snapshot.
2. Encode the holder as `uint256(uint160(holder))`.
3. Call `beginVesting` after the reward round completes.
4. Call `collectVestedRewards` to the holder as rewards unlock.

## Recycling

1. Wait until the reward round claim deadline has passed.
2. Call `recycleExpiredRewards(address(JBX), token, rounds)`.
3. Verify only the unmaterialized amount entered the current reward round.
