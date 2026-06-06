# Skills

Use this index to route maintenance work quickly.

| Task | Start Here |
| --- | --- |
| JBX reward math | `src/JBXDistributor.sol` `_tokenStakeAt`, `_totalStake`, `_claimRewardRoundFor` |
| Split hook auth | `src/JBXDistributor.sol` `processSplitWith`, `_requireSplitCaller` |
| Remote bridge queue | `src/JBXDistributor.sol` `bridgeToMainnet` |
| Mainnet settlement | `src/JBXDistributor.sol` `claimRemoteRewards` |
| Vesting and collection | `src/JBDistributor.sol` `_beginVesting`, `_collectVestedRewards`, `_unlockRewards` |
| Expiry recycling | `src/JBDistributor.sol` `_recycleExpiredRewardRound` |
| Tests | `test/JBXDistributor.t.sol` |

High-level documents:

- `ARCHITECTURE.md`
- `USER_JOURNEYS.md`
- `INVARIANTS.md`
- `RISKS.md`
- `ADMINISTRATION.md`
