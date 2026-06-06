// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBActiveVotes} from "@bananapus/core-v6/src/interfaces/IJBActiveVotes.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBClaim} from "@bananapus/suckers-v6/src/structs/JBClaim.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IJBDistributor} from "./IJBDistributor.sol";

/// @notice Distributes split-funded rewards to mainnet JBX stakers with delegated voting power.
/// @dev Projects submit rewards through split hooks. Mainnet split deposits become JBX-staker reward rounds directly.
/// Remote split deposits are project tokens that can be bridged to mainnet through that project's sucker, then settled
/// into the same JBX-staker reward ledger.
interface IJBXDistributor is IJBDistributor, IJBSplitHook {
    //*********************************************************************//
    // -------------------------------- events --------------------------- //
    //*********************************************************************//

    /// @notice Emitted when a remote project's pending rewards are cashed out into a sucker leaf for mainnet.
    /// @param originChainId The chain that prepared the bridge.
    /// @param projectId The project whose token rewards were bridged.
    /// @param sucker The sucker that prepared the bridge leaf.
    /// @param terminalToken The terminal token cashed out into for the bridge.
    /// @param amount The number of project tokens bridged.
    /// @param leafMetadata The metadata written into the sucker leaf.
    /// @param caller The address that prepared the bridge.
    event BridgeToMainnet(
        uint256 indexed originChainId,
        uint256 indexed projectId,
        IJBSucker sucker,
        address terminalToken,
        uint256 amount,
        bytes32 leafMetadata,
        address caller
    );

    /// @notice Emitted when a sucker leaf had already been claimed, and this contract authenticated the leaf hash.
    /// @param originChainId The chain that prepared the bridge.
    /// @param projectId The project whose token rewards were claimed.
    /// @param leafIndex The leaf index in the sucker inbox.
    /// @param rewardAmount The number of project tokens settled into JBX rewards.
    /// @param caller The address that settled the already-claimed leaf.
    event ClaimedFromFrontRun(
        uint256 indexed originChainId,
        uint256 indexed projectId,
        uint256 indexed leafIndex,
        uint256 rewardAmount,
        address caller
    );

    /// @notice Emitted when the admin permanently sets the JBX staking token.
    /// @param jbx The JBX staking token.
    /// @param caller The address that set the token.
    event JBXSet(IJBActiveVotes indexed jbx, address caller);

    /// @notice Emitted when a bridged reward leaf is settled into the mainnet JBX reward ledger.
    /// @param originChainId The chain that prepared the bridge.
    /// @param projectId The project whose token rewards were claimed.
    /// @param terminalToken The terminal token claimed from the sucker leaf.
    /// @param terminalReceived The amount of terminal tokens added back to the destination project.
    /// @param rewardToken The destination project token recorded as rewards for JBX stakers.
    /// @param rewardAmount The number of destination project tokens recorded as rewards.
    /// @param caller The address that settled the reward leaf.
    event RemoteRewardsClaimed(
        uint256 indexed originChainId,
        uint256 indexed projectId,
        address indexed terminalToken,
        uint256 terminalReceived,
        IERC20 rewardToken,
        uint256 rewardAmount,
        address caller
    );

    /// @notice Emitted when a split deposit is accepted into the local reward ledger or remote bridge queue.
    /// @param projectId The project whose split funded rewards.
    /// @param token The token received from the split.
    /// @param amount The amount accepted.
    /// @param queuedForBridge Whether the amount is waiting for a sucker bridge to mainnet.
    /// @param caller The address that called the split hook.
    event SplitRewardsAccepted(
        uint256 indexed projectId, IERC20 indexed token, uint256 amount, bool queuedForBridge, address caller
    );

    //*********************************************************************//
    // ----------------------------- views ------------------------------- //
    //*********************************************************************//

    /// @notice The JB directory used to verify terminal/controller callers.
    /// @return directory The JB directory.
    function DIRECTORY() external view returns (IJBDirectory directory);

    /// @notice The JBX token whose delegated holders receive rewards.
    /// @return jbx The JBX staking token.
    function JBX() external view returns (IJBActiveVotes jbx);

    /// @notice The chain ID where JBX rewards are distributed.
    /// @return mainnetChainId The mainnet chain ID.
    function MAINNET_CHAIN_ID() external view returns (uint256 mainnetChainId);

    /// @notice The sucker registry used to authenticate cross-chain project suckers.
    /// @return suckerRegistry The sucker registry.
    function SUCKER_REGISTRY() external view returns (IJBSuckerRegistry suckerRegistry);

    /// @notice The JB token registry used to resolve each project's project token.
    /// @return tokens The token registry.
    function TOKENS() external view returns (IJBTokens tokens);

    /// @notice Pack bridge attribution into the sucker leaf metadata.
    /// @param originChainId The chain that prepared the bridge.
    /// @param projectId The project whose rewards are being bridged.
    /// @return metadata The packed metadata.
    function packLeafMetadata(uint256 originChainId, uint256 projectId) external pure returns (bytes32 metadata);

    /// @notice The amount of remote-chain project tokens waiting to be bridged to mainnet.
    /// @param projectId The project whose pending rewards are being read.
    /// @param token The project token waiting to be bridged.
    /// @return amount The amount pending.
    function pendingBridgeAmountOf(uint256 projectId, IERC20 token) external view returns (uint256 amount);

    /// @notice Whether a sucker leaf has already been settled into JBX rewards.
    /// @param sucker The sucker that produced the leaf.
    /// @param terminalToken The terminal token of the leaf.
    /// @param leafIndex The leaf index in the sucker inbox tree.
    /// @return settled Whether the leaf has been settled.
    function settledLeafOf(IJBSucker sucker, address terminalToken, uint256 leafIndex) external view returns (bool);

    //*********************************************************************//
    // ---------------------------- transactions ------------------------- //
    //*********************************************************************//

    /// @notice Bridge remote-chain project-token rewards to the mainnet distributor through the project's sucker.
    /// @param projectId The project whose token rewards should be bridged.
    /// @param sucker The project sucker that peers to mainnet.
    /// @param terminalToken The terminal token to cash out into for the bridge.
    /// @param amount The number of project tokens to bridge.
    /// @param minTokensReclaimed The minimum terminal tokens the sucker must reclaim.
    /// @return bridged The number of project tokens prepared for mainnet.
    function bridgeToMainnet(
        uint256 projectId,
        IJBSucker sucker,
        address terminalToken,
        uint256 amount,
        uint256 minTokensReclaimed
    )
        external
        returns (uint256 bridged);

    /// @notice Settle a proven sucker leaf into the mainnet JBX reward ledger.
    /// @param originChainId The chain that prepared the bridge.
    /// @param projectId The project whose token rewards are being settled.
    /// @param sucker The project sucker the claim belongs to.
    /// @param claimData The terminal token, leaf, and Merkle proof from the bridge.
    /// @return rewardAmount The number of destination project tokens recorded as rewards.
    function claimRemoteRewards(
        uint256 originChainId,
        uint256 projectId,
        IJBSucker sucker,
        JBClaim calldata claimData
    )
        external
        returns (uint256 rewardAmount);

    /// @notice Permanently set the JBX token whose active voters receive rewards.
    /// @param jbx The JBX token.
    function setJBX(IJBActiveVotes jbx) external;
}
