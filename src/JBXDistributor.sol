// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBActiveVotes} from "@bananapus/core-v6/src/interfaces/IJBActiveVotes.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBToken} from "@bananapus/core-v6/src/interfaces/IJBToken.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {JBSuckerState} from "@bananapus/suckers-v6/src/enums/JBSuckerState.sol";
import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBClaim} from "@bananapus/suckers-v6/src/structs/JBClaim.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import {JBDistributor} from "./JBDistributor.sol";
import {IJBDistributor} from "./interfaces/IJBDistributor.sol";
import {IJBXDistributor} from "./interfaces/IJBXDistributor.sol";
import {IREVLoans} from "./interfaces/IREVLoans.sol";
import {IREVOwner} from "./interfaces/IREVOwner.sol";
import {JBClaimContext} from "./structs/JBClaimContext.sol";
import {JBRewardRoundData} from "./structs/JBRewardRoundData.sol";
import {JBVestingData} from "./structs/JBVestingData.sol";

/// @notice Distributes split-funded rewards to mainnet JBX stakers with delegated voting power and linear vesting.
/// @dev The JBX staking token is set once by the owner. Mainnet splits fund JBX reward rounds directly. Remote splits
/// queue project tokens for a permissionless `bridgeToMainnet` call through that project's sucker, and mainnet
/// `claimRemoteRewards` settles the proven leaf into the same JBX reward ledger.
contract JBXDistributor is JBDistributor, Ownable, IJBXDistributor {
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    /// @notice Thrown when the claimed sucker leaf beneficiary is not this distributor.
    error JBXDistributor_LeafBeneficiaryMismatch(bytes32 expected, bytes32 got);

    /// @notice Thrown when a sucker leaf has already been settled into JBX rewards.
    error JBXDistributor_LeafAlreadySettled(address sucker, address terminalToken, uint256 leafIndex);

    /// @notice Thrown when the claimed sucker leaf metadata does not match the asserted source project.
    error JBXDistributor_LeafMetadataMismatch(bytes32 expected, bytes32 got);

    /// @notice Thrown when a chain ID cannot fit in the packed leaf metadata.
    error JBXDistributor_ChainIdTooLarge(uint256 chainId);

    /// @notice Thrown when direct funding is attempted instead of split-hook funding.
    error JBXDistributor_DirectFundingDisabled();

    /// @notice Thrown when an encoded staker token ID has nonzero bits above the address width.
    error JBXDistributor_InvalidTokenId(uint256 tokenId);

    /// @notice Thrown when the caller provides an invalid project ID.
    error JBXDistributor_InvalidProjectId(uint256 projectId);

    /// @notice Thrown when the owner tries to set the JBX token more than once.
    error JBXDistributor_JBXAlreadySet(IJBActiveVotes jbx);

    /// @notice Thrown when a funding or claim path needs the JBX token before the owner has set it.
    error JBXDistributor_JBXNotSet();

    /// @notice Thrown when a function can only be used on the configured mainnet chain.
    error JBXDistributor_MainnetOnly(uint256 chainId, uint256 mainnetChainId);

    /// @notice Thrown when native ETH does not match the split hook context amount.
    error JBXDistributor_NativeAmountMismatch(uint256 msgValue, uint256 contextAmount);

    /// @notice Thrown when a sucker is not registered for the specified project.
    error JBXDistributor_NotASucker(uint256 projectId, address sucker);

    /// @notice Thrown when a project ID cannot fit in the packed leaf metadata.
    error JBXDistributor_ProjectIdTooLarge(uint256 projectId);

    /// @notice Thrown when a claim's executed-leaf hash does not match the caller-provided leaf data.
    error JBXDistributor_FrontRunLeafMismatch(bytes32 expected, bytes32 stored);

    /// @notice Thrown when a hook-keyed inherited function is called for something other than JBX.
    error JBXDistributor_OnlyJBX(address hook, address jbx);

    /// @notice Thrown when a function can only be used away from the configured mainnet chain.
    error JBXDistributor_RemoteOnly(uint256 chainId, uint256 mainnetChainId);

    /// @notice Thrown when the owner tries to set JBX to the zero address.
    error JBXDistributor_ZeroJBX();

    /// @notice Thrown when an amount exceeds the remote split rewards queued for a project token.
    error JBXDistributor_InsufficientPendingBridgeAmount(uint256 amount, uint256 pendingAmount);

    /// @notice Thrown when a split carries a token that cannot be bridged by the project's sucker.
    error JBXDistributor_SplitTokenNotBridgeable(uint256 projectId, address token, address expectedToken);

    /// @notice Thrown when the sucker is not in a sending-enabled state.
    error JBXDistributor_SuckerNotSending(address sucker, JBSuckerState state);

    /// @notice Thrown when the sucker does not belong to the specified project.
    error JBXDistributor_SuckerProjectMismatch(uint256 projectId, uint256 suckerProjectId);

    /// @notice Thrown when the sucker does not peer to the configured mainnet chain.
    error JBXDistributor_SuckerPeerMismatch(uint256 expectedChainId, uint256 actualChainId);

    /// @notice Thrown when native ETH is sent with an ERC-20 split.
    error JBXDistributor_TokenMismatch(address token, address expectedToken, uint256 msgValue);

    /// @notice Thrown when the caller is not a terminal or controller for the project.
    error JBXDistributor_Unauthorized(uint256 projectId, address caller);

    /// @notice Thrown when a zero chain ID is provided.
    error JBXDistributor_ZeroChainId();

    /// @notice Thrown when a project has no ERC-20 token to bridge or settle as rewards.
    error JBXDistributor_ZeroProjectToken(uint256 projectId);

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice The JB directory that verifies terminal/controller callers.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The chain ID where JBX rewards are distributed.
    uint256 public immutable override MAINNET_CHAIN_ID;

    /// @notice The sucker registry that authenticates cross-chain project suckers.
    IJBSuckerRegistry public immutable override SUCKER_REGISTRY;

    /// @notice The JB token registry that resolves each project's project token.
    IJBTokens public immutable override TOKENS;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The JBX token whose delegated holders receive rewards.
    IJBActiveVotes public override JBX;

    /// @notice The next reward round a JBX staker has not yet claimed.
    /// @custom:param hook The configured JBX token.
    /// @custom:param groupId The reward group (0 = the default group).
    /// @custom:param tokenId The encoded staker address.
    /// @custom:param token The reward token being claimed.
    mapping(
        address hook => mapping(uint256 groupId => mapping(uint256 tokenId => mapping(IERC20 token => uint256)))
    ) public nextClaimRoundOf;

    /// @notice The amount of remote-chain project tokens waiting to be bridged to mainnet.
    /// @custom:param projectId The project whose pending rewards are queued.
    /// @custom:param token The project token waiting to be bridged.
    mapping(uint256 projectId => mapping(IERC20 token => uint256 amount)) public override pendingBridgeAmountOf;

    /// @notice Whether a sucker leaf has already been settled into JBX rewards.
    /// @custom:param sucker The sucker that produced the leaf.
    /// @custom:param terminalToken The terminal token of the leaf.
    /// @custom:param leafIndex The leaf index in the sucker inbox tree.
    mapping(IJBSucker sucker => mapping(address terminalToken => mapping(uint256 leafIndex => bool)))
        public
        override settledLeafOf;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @notice Initializes the JBX distributor.
    /// @param directory The JB directory that verifies terminal/controller callers.
    /// @param controller The JB controller for token registry lookups and revnet loan permissions.
    /// @param tokens The JB token registry that resolves each project's project token.
    /// @param suckerRegistry The sucker registry that authenticates project suckers.
    /// @param revLoans The Revnet loans contract that borrows against vested revnet rewards.
    /// @param revOwner The REVOwner contract that must own revnet reward token projects.
    /// @param owner The admin allowed to set JBX once.
    /// @param mainnetChainId The chain ID where JBX rewards are distributed.
    /// @param initialRoundDuration The duration of each round, specified in seconds.
    /// @param initialVestingRounds The number of rounds until tokens are fully vested.
    /// @param initialClaimDuration The number of seconds claimants have after each reward round becomes claimable.
    constructor(
        IJBDirectory directory,
        IJBController controller,
        IJBTokens tokens,
        IJBSuckerRegistry suckerRegistry,
        IREVLoans revLoans,
        IREVOwner revOwner,
        address owner,
        uint256 mainnetChainId,
        uint256 initialRoundDuration,
        uint256 initialVestingRounds,
        uint48 initialClaimDuration
    )
        JBDistributor(controller, revLoans, revOwner, initialRoundDuration, initialVestingRounds, initialClaimDuration)
        Ownable(owner)
    {
        if (mainnetChainId == 0) revert JBXDistributor_ZeroChainId();

        DIRECTORY = directory;
        MAINNET_CHAIN_ID = mainnetChainId;
        SUCKER_REGISTRY = suckerRegistry;
        TOKENS = tokens;
    }

    //*********************************************************************//
    // ------------------------- receive / fallback ---------------------- //
    //*********************************************************************//

    /// @notice Allows the contract to receive native ETH from mainnet payout splits.
    receive() external payable {}

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Begin vesting all unclaimed past reward rounds for the specified encoded JBX staker addresses.
    /// @dev Convenience wrapper around the inherited hook-keyed API. Permissionless helpers can start vesting for any
    /// staker, but rewards stay assigned to the encoded staker address.
    /// @param tokenIds The encoded JBX staker addresses to claim rewards for.
    /// @param tokens The reward tokens to begin vesting.
    function beginVesting(uint256[] calldata tokenIds, IERC20[] calldata tokens) external {
        _beginVesting({hook: _jbxAddress(), groupId: 0, tokenIds: tokenIds, tokens: tokens});
    }

    /// @notice Begin vesting all unclaimed past reward rounds for JBX stakers.
    /// @dev Overrides the inherited hook-keyed API so callers cannot point vesting at any token other than JBX.
    /// @param hook The configured JBX token.
    /// @param tokenIds The encoded JBX staker addresses to claim rewards for.
    /// @param tokens The reward tokens to begin vesting.
    function beginVesting(
        address hook,
        uint256[] calldata tokenIds,
        IERC20[] calldata tokens
    )
        external
        override(IJBDistributor, JBDistributor)
    {
        _requireJBXHook(hook);
        _beginVesting({hook: hook, groupId: 0, tokenIds: tokenIds, tokens: tokens});
    }

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
        override
        returns (uint256 bridged)
    {
        if (block.chainid == MAINNET_CHAIN_ID) {
            revert JBXDistributor_RemoteOnly({chainId: block.chainid, mainnetChainId: MAINNET_CHAIN_ID});
        }
        if (projectId == 0) revert JBXDistributor_InvalidProjectId({projectId: projectId});

        // The source-side queued token must be the project's ERC-20 because suckers bridge by cashing out project
        // tokens into terminal tokens.
        IERC20 projectToken = _projectTokenOf(projectId);

        // Respect the caller's explicit amount so a keeper can choose bridge size and slippage together.
        uint256 pendingAmount = pendingBridgeAmountOf[projectId][projectToken];
        if (amount > pendingAmount) {
            revert JBXDistributor_InsufficientPendingBridgeAmount({amount: amount, pendingAmount: pendingAmount});
        }

        // Zero prepares are rejected by the sucker; returning 0 keeps empty keeper calls cheap and harmless.
        if (amount == 0) return 0;

        // The sucker must be the project's registered, sending-enabled pair to mainnet.
        _requireMainnetSucker({projectId: projectId, sucker: sucker});

        // Advance pending accounting before the external call so reentrancy cannot bridge the same tokens twice.
        pendingBridgeAmountOf[projectId][projectToken] = pendingAmount - amount;

        // Metadata authenticates the source chain and project during mainnet settlement.
        bytes32 leafMetadata = packLeafMetadata({originChainId: block.chainid, projectId: projectId});

        // Grant the sucker only the project tokens being bridged, then clear the allowance after `prepare`.
        projectToken.forceApprove({spender: address(sucker), value: amount});
        sucker.prepare({
            projectTokenCount: amount,
            beneficiary: _toBytes32(address(this)),
            minTokensReclaimed: minTokensReclaimed,
            token: terminalToken,
            metadata: leafMetadata
        });
        projectToken.forceApprove({spender: address(sucker), value: 0});

        emit BridgeToMainnet({
            originChainId: block.chainid,
            projectId: projectId,
            sucker: sucker,
            terminalToken: terminalToken,
            amount: amount,
            leafMetadata: leafMetadata,
            caller: msg.sender
        });

        bridged = amount;
    }

    /// @notice Settle a proven sucker leaf into the mainnet JBX reward ledger.
    /// @param originChainId The chain that prepared the bridge.
    /// @param originProjectId The origin-chain project whose leaf is being settled.
    /// @param mainnetProjectId The mainnet project whose token rewards are being settled.
    /// @param sucker The project sucker the claim belongs to.
    /// @param claimData The terminal token, leaf, and Merkle proof from the bridge.
    /// @return rewardAmount The number of destination project tokens recorded as rewards.
    function claimRemoteRewards(
        uint256 originChainId,
        uint256 originProjectId,
        uint256 mainnetProjectId,
        IJBSucker sucker,
        JBClaim calldata claimData
    )
        external
        override
        returns (uint256 rewardAmount)
    {
        if (block.chainid != MAINNET_CHAIN_ID) {
            revert JBXDistributor_MainnetOnly({chainId: block.chainid, mainnetChainId: MAINNET_CHAIN_ID});
        }
        if (originChainId == 0) revert JBXDistributor_ZeroChainId();
        if (originChainId == block.chainid) {
            revert JBXDistributor_MainnetOnly({chainId: originChainId, mainnetChainId: MAINNET_CHAIN_ID});
        }
        if (originProjectId == 0) revert JBXDistributor_InvalidProjectId({projectId: originProjectId});
        if (mainnetProjectId == 0) revert JBXDistributor_InvalidProjectId({projectId: mainnetProjectId});

        _requireNotAcceptingToken();

        // JBX must be set before rewards can enter the mainnet reward ledger.
        address jbx = _jbxAddress();

        // The sucker must be registered for the mainnet project that mints reward tokens to this contract.
        _requireOriginSucker({mainnetProjectId: mainnetProjectId, originChainId: originChainId, sucker: sucker});

        // The leaf must mint project tokens to this distributor; the sucker proof authenticates the leaf contents.
        bytes32 expectedBeneficiary = _toBytes32(address(this));
        if (claimData.leaf.beneficiary != expectedBeneficiary) {
            revert JBXDistributor_LeafBeneficiaryMismatch({
                expected: expectedBeneficiary, got: claimData.leaf.beneficiary
            });
        }

        // The leaf metadata binds the reward to the asserted source chain and project.
        bytes32 expectedMetadata = packLeafMetadata({originChainId: originChainId, projectId: originProjectId});
        if (claimData.leaf.metadata != expectedMetadata) {
            revert JBXDistributor_LeafMetadataMismatch({expected: expectedMetadata, got: claimData.leaf.metadata});
        }

        // Each sucker leaf can fund JBX rewards once, even if an external caller already executed the sucker claim.
        if (settledLeafOf[sucker][claimData.token][claimData.leaf.index]) {
            revert JBXDistributor_LeafAlreadySettled({
                sucker: address(sucker), terminalToken: claimData.token, leafIndex: claimData.leaf.index
            });
        }

        // Destination project tokens are the reward token JBX stakers will claim.
        IERC20 rewardToken = _projectTokenOf(mainnetProjectId);

        // Reserve the leaf before the external claim. Reverts roll this write back and keep failed claims retryable.
        settledLeafOf[sucker][claimData.token][claimData.leaf.index] = true;

        // A direct `sucker.claim` can be front-run because it is permissionless. Authenticate already-executed leaves
        // by matching the hash the sucker stored at execution time.
        bytes32 storedHash = sucker.executedLeafHashOf(claimData.token, claimData.leaf.index);
        if (storedHash != bytes32(0)) {
            bytes32 expectedHash = keccak256(
                abi.encodePacked(
                    claimData.leaf.projectTokenCount,
                    claimData.leaf.terminalTokenAmount,
                    claimData.leaf.beneficiary,
                    claimData.leaf.metadata
                )
            );
            if (storedHash != expectedHash) {
                revert JBXDistributor_FrontRunLeafMismatch({expected: expectedHash, stored: storedHash});
            }

            // The front-run claim already minted the destination project tokens to this distributor.
            rewardAmount = claimData.leaf.projectTokenCount;
            emit ClaimedFromFrontRun({
                originChainId: originChainId,
                projectId: mainnetProjectId,
                leafIndex: claimData.leaf.index,
                rewardAmount: rewardAmount,
                caller: msg.sender
            });
        } else {
            // Measure the exact project-token balance delta minted by `sucker.claim`.
            _acceptingToken = address(rewardToken);
            uint256 rewardBalanceBefore = rewardToken.balanceOf(address(this));
            sucker.claim(claimData);
            rewardAmount = rewardToken.balanceOf(address(this)) - rewardBalanceBefore;
            _acceptingToken = address(0);
        }

        // Mainnet remote rewards join the same current-round JBX ledger as same-chain split rewards.
        _recordRewardFunding({hook: jbx, groupId: 0, token: rewardToken, amount: rewardAmount});

        emit RemoteRewardsClaimed({
            originChainId: originChainId,
            projectId: mainnetProjectId,
            terminalToken: claimData.token,
            terminalReceived: claimData.leaf.terminalTokenAmount,
            rewardToken: rewardToken,
            rewardAmount: rewardAmount,
            caller: msg.sender
        });
    }

    /// @notice Receives rewards from a Juicebox split.
    /// @dev Mainnet deposits become JBX reward rounds immediately. Remote deposits must be project tokens so they can
    /// be bridged to mainnet through the project's sucker.
    /// @param context The split hook context from the terminal or controller.
    function processSplitWith(JBSplitHookContext calldata context) external payable override {
        _requireSplitCaller(context);

        // Mainnet distributions can accept any payout/reserved token. Remote distributions must queue the project
        // token, because `bridgeToMainnet` uses `sucker.prepare` which pulls project tokens.
        bool isMainnet = block.chainid == MAINNET_CHAIN_ID;
        IERC20 projectToken;
        if (!isMainnet) projectToken = _projectTokenOf(context.projectId);

        if (context.token == JBConstants.NATIVE_TOKEN) {
            if (!isMainnet) {
                revert JBXDistributor_SplitTokenNotBridgeable({
                    projectId: context.projectId, token: context.token, expectedToken: address(projectToken)
                });
            }

            if (msg.value != context.amount) {
                revert JBXDistributor_NativeAmountMismatch({msgValue: msg.value, contextAmount: context.amount});
            }

            if (msg.value != 0) {
                _recordRewardFunding({
                    hook: _jbxAddress(), groupId: 0, token: IERC20(JBConstants.NATIVE_TOKEN), amount: msg.value
                });
                emit SplitRewardsAccepted({
                    projectId: context.projectId,
                    token: IERC20(JBConstants.NATIVE_TOKEN),
                    amount: msg.value,
                    queuedForBridge: false,
                    caller: msg.sender
                });
            }

            return;
        }

        // ERC-20 split calls should not carry native ETH.
        if (msg.value != 0) {
            revert JBXDistributor_TokenMismatch({
                token: context.token, expectedToken: JBConstants.NATIVE_TOKEN, msgValue: msg.value
            });
        }

        // Zero-amount split hooks are successful no-ops so controllers and terminals can keep processing splits.
        if (context.amount == 0) return;

        IERC20 token = IERC20(context.token);

        if (!isMainnet && context.token != address(projectToken)) {
            revert JBXDistributor_SplitTokenNotBridgeable({
                projectId: context.projectId, token: context.token, expectedToken: address(projectToken)
            });
        }

        // Pull the split allowance and credit the actual balance delta to support fee-on-transfer reward tokens.
        uint256 delta = _acceptErc20FundsFrom({token: token, from: msg.sender, amount: context.amount});
        if (isMainnet) {
            _recordRewardFunding({hook: _jbxAddress(), groupId: 0, token: token, amount: delta});
        } else {
            // Remote project tokens wait in this hook until a keeper prepares the sucker bridge.
            pendingBridgeAmountOf[context.projectId][token] += delta;
        }

        emit SplitRewardsAccepted({
            projectId: context.projectId, token: token, amount: delta, queuedForBridge: !isMainnet, caller: msg.sender
        });
    }

    /// @notice Permanently set the JBX token whose active voters receive rewards.
    /// @param jbx The JBX token.
    function setJBX(IJBActiveVotes jbx) external override onlyOwner {
        if (address(jbx) == address(0)) revert JBXDistributor_ZeroJBX();
        if (address(JBX) != address(0)) revert JBXDistributor_JBXAlreadySet({jbx: JBX});

        // Store JBX once so no later split can redirect the reward constituency.
        JBX = jbx;

        emit JBXSet({jbx: jbx, caller: msg.sender});
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Pack bridge attribution into the sucker leaf metadata.
    /// @param originChainId The chain that prepared the bridge.
    /// @param projectId The project whose rewards are being bridged.
    /// @return metadata The packed metadata.
    function packLeafMetadata(uint256 originChainId, uint256 projectId)
        public
        pure
        override
        returns (bytes32 metadata)
    {
        if (originChainId > type(uint32).max) {
            revert JBXDistributor_ChainIdTooLarge({chainId: originChainId});
        }
        if (projectId > type(uint64).max) revert JBXDistributor_ProjectIdTooLarge({projectId: projectId});

        // Layout: bits [95:64] = originChainId, bits [63:0] = projectId. Upper bits are reserved.
        metadata = bytes32((originChainId << 64) | projectId);
    }

    /// @notice Indicates whether this contract supports the given interface.
    /// @param interfaceId The interface ID to check.
    /// @return A flag indicating support.
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IJBXDistributor).interfaceId || interfaceId == type(IJBSplitHook).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    //*********************************************************************//
    // ----------------------- public transactions ----------------------- //
    //*********************************************************************//

    /// @notice Borrow from a revnet using one JBX staker's uncollected vesting rewards as collateral.
    /// @dev Overrides the inherited hook-keyed API so callers cannot borrow against any reward pool other than JBX.
    /// @param hook The configured JBX token.
    /// @param tokenIds The single encoded JBX staker address to borrow against.
    /// @param tokens The single revnet reward token to collateralize.
    /// @param sourceToken The token to borrow from the revnet.
    /// @param minBorrowAmount The minimum amount to borrow, denominated in `sourceToken`.
    /// @param prepaidFeePercent The fee percent to charge upfront.
    /// @param beneficiary The recipient of the borrowed funds.
    /// @return loanId The Revnet loan NFT ID held by this distributor.
    /// @return collateralCount The amount of vesting rewards used as collateral.
    function borrowAgainstVesting(
        address hook,
        uint256[] calldata tokenIds,
        IERC20[] calldata tokens,
        address sourceToken,
        uint256 minBorrowAmount,
        uint256 prepaidFeePercent,
        address payable beneficiary
    )
        public
        override(IJBDistributor, JBDistributor)
        returns (uint256 loanId, uint256 collateralCount)
    {
        _requireJBXHook(hook);
        (loanId, collateralCount) = _borrowAgainstVestingFor({
            hook: hook,
            groupId: 0,
            tokenIds: tokenIds,
            tokens: tokens,
            sourceToken: sourceToken,
            minBorrowAmount: minBorrowAmount,
            prepaidFeePercent: prepaidFeePercent,
            beneficiary: beneficiary
        });
    }

    /// @notice Begin vesting unclaimed rewards, then collect everything unlocked to the beneficiary.
    /// @dev Overrides the inherited hook-keyed API so callers cannot collect from any reward pool other than JBX.
    /// @param hook The configured JBX token.
    /// @param tokenIds The encoded JBX staker addresses to collect for.
    /// @param tokens The reward tokens to collect.
    /// @param beneficiary The recipient of collected rewards.
    function collectVestedRewards(
        address hook,
        uint256[] calldata tokenIds,
        IERC20[] calldata tokens,
        address beneficiary
    )
        public
        override(IJBDistributor, JBDistributor)
    {
        _requireJBXHook(hook);
        _collectVestedRewards({hook: hook, groupId: 0, tokenIds: tokenIds, tokens: tokens, beneficiary: beneficiary});
    }

    /// @notice Reject direct funding because JBX rewards must arrive through split hooks or sucker settlement.
    /// @param hook Unused.
    /// @param token Unused.
    /// @param amount Unused.
    function fund(address hook, IERC20 token, uint256 amount) public payable override(IJBDistributor, JBDistributor) {
        hook;
        token;
        amount;
        revert JBXDistributor_DirectFundingDisabled();
    }

    /// @notice Recycle unclaimed rewards from expired JBX reward rounds into the current reward round.
    /// @dev Overrides the inherited hook-keyed API so callers cannot recycle any reward pool other than JBX.
    /// @param hook The configured JBX token.
    /// @param token The reward token to recycle.
    /// @param rounds The reward rounds to recycle.
    /// @return amount The total amount recycled.
    function recycleExpiredRewards(
        address hook,
        IERC20 token,
        uint256[] calldata rounds
    )
        public
        override(IJBDistributor, JBDistributor)
        returns (uint256 amount)
    {
        _requireJBXHook(hook);
        amount = _recycleExpiredRewards({hook: hook, groupId: 0, token: token, rounds: rounds});
    }

    /// @notice Recycle forfeited rewards from burned staker token IDs.
    /// @dev JBX staker IDs are encoded addresses, so there is no burned-token recycling path.
    /// @param hook The configured JBX token.
    /// @param tokenIds The encoded staker addresses.
    /// @param tokens The reward tokens to recycle.
    /// @param beneficiary Unused for forfeiture.
    function releaseForfeitedRewards(
        address hook,
        uint256[] calldata tokenIds,
        IERC20[] calldata tokens,
        address beneficiary
    )
        public
        override(IJBDistributor, JBDistributor)
    {
        _requireJBXHook(hook);
        _releaseForfeitedRewards({hook: hook, groupId: 0, tokenIds: tokenIds, tokens: tokens, beneficiary: beneficiary});
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Claim all past reward rounds for the given stakers and reward tokens into fresh vesting entries.
    /// @param hook The configured JBX token.
    /// @param groupId The reward group being claimed.
    /// @param tokenIds The encoded staker addresses to claim for.
    /// @param tokens The reward tokens to claim.
    function _claimPastRewards(
        address hook,
        uint256 groupId,
        uint256[] calldata tokenIds,
        IERC20[] calldata tokens
    )
        internal
        override
    {
        // Round 0 has no completed reward rounds behind it, so nothing can be claimed yet.
        uint256 round = currentRound();
        if (round == 0) return;

        // Current-round funding becomes claimable only after a later round starts.
        JBClaimContext memory ctx = JBClaimContext({
            hook: hook, groupId: groupId, lastClaimableRound: round - 1, vestingReleaseRound: round + VESTING_ROUNDS
        });

        // Process each reward token independently because each token has its own funding and claim cursor.
        for (uint256 i; i < tokens.length;) {
            IERC20 token = tokens[i];
            uint256 totalVestingAmount;

            // Materialize this reward token for every staker address encoded in tokenIds.
            for (uint256 j; j < tokenIds.length;) {
                uint256 tokenId = tokenIds[j];
                uint256 tokenAmount = _claimPastRewardsForTokenId({ctx: ctx, tokenId: tokenId, token: token});

                // Accumulate once per reward token so totalVestingAmountOf is updated with one storage write.
                totalVestingAmount += tokenAmount;

                unchecked {
                    ++j;
                }
            }

            // Track the newly claimed amount as vesting, so later collections unlock against it over time.
            if (totalVestingAmount != 0) totalVestingAmountOf[hook][token] += totalVestingAmount;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Claim all past reward rounds for one staker into one fresh vesting entry.
    /// @param ctx The claim-round context.
    /// @param tokenId The encoded staker address to claim for.
    /// @param token The reward token to claim.
    /// @return tokenAmount The amount added to vesting.
    function _claimPastRewardsForTokenId(
        JBClaimContext memory ctx,
        uint256 tokenId,
        IERC20 token
    )
        internal
        returns (uint256 tokenAmount)
    {
        // Load this staker's cursor for the reward token. All earlier rounds have already been settled.
        uint256 nextClaimRound = nextClaimRoundOf[ctx.hook][ctx.groupId][tokenId][token];

        // If the cursor is already past the last completed round, this staker is current.
        if (nextClaimRound > ctx.lastClaimableRound) return 0;

        // Sum this staker's pro-rata share from every resolved completed reward round.
        uint256 newNextClaimRound;
        (tokenAmount, newNextClaimRound) = _claimRewardsFor({
            hook: ctx.hook,
            groupId: ctx.groupId,
            tokenId: tokenId,
            token: token,
            firstRound: nextClaimRound,
            lastRound: ctx.lastClaimableRound
        });

        // Advance the cursor through resolved rounds.
        nextClaimRoundOf[ctx.hook][ctx.groupId][tokenId][token] = newNextClaimRound;

        // Avoid writing empty vesting entries when no past round allocates rewards to this staker.
        if (tokenAmount == 0) return 0;

        // All accumulated past rewards start a single fresh vesting schedule at the claim round.
        vestingDataOf[ctx.hook][ctx.groupId][tokenId][token].push(
            JBVestingData({releaseRound: ctx.vestingReleaseRound, amount: tokenAmount, shareClaimed: 0})
        );

        emit Claimed({
            hook: ctx.hook,
            tokenId: tokenId,
            groupId: ctx.groupId,
            token: token,
            amount: tokenAmount,
            vestingReleaseRound: ctx.vestingReleaseRound,
            caller: msg.sender
        });
    }

    /// @notice Claim one reward round using its recorded denominator.
    /// @param hook The configured JBX token.
    /// @param tokenId The encoded staker address.
    /// @param rewardRound The stored reward-round data.
    /// @return tokenAmount The amount added to vesting.
    function _claimRewardRoundFor(
        address hook,
        uint256 tokenId,
        JBRewardRoundData storage rewardRound
    )
        internal
        returns (uint256 tokenAmount)
    {
        // Empty-denominator rounds have no pro-rata basis, so they cannot allocate rewards to any staker.
        if (rewardRound.totalStake == 0) return 0;

        // Use the funding round's snapshot block, not the block at which the staker finally claims.
        uint256 tokenStakeAmount = _tokenStakeAt({hook: hook, tokenId: tokenId, blockNumber: rewardRound.snapshotBlock});

        // Zero-vote stakers advance their cursor but do not consume reward inventory.
        if (tokenStakeAmount == 0) return 0;

        // The round's reward pot is split pro-rata across checkpointed active voting power.
        uint256 claimAmount = mulDiv({x: rewardRound.amount, y: tokenStakeAmount, denominator: rewardRound.totalStake});

        // Ignore floor-rounded zero claims to avoid unnecessary storage writes.
        if (claimAmount == 0) return 0;

        // Track the portion that has started vesting so expiry recycles only the remainder.
        rewardRound.claimedAmount = _toUint208(uint256(rewardRound.claimedAmount) + claimAmount);

        // Return the exact amount that the caller should append to the staker's vesting entry.
        tokenAmount = claimAmount;
    }

    /// @notice Claim a staker's unclaimed rewards across a range of historical reward rounds.
    /// @param hook The configured JBX token.
    /// @param groupId The reward group being claimed.
    /// @param tokenId The encoded staker address.
    /// @param token The reward token.
    /// @param firstRound The first reward round to include.
    /// @param lastRound The last reward round to include.
    /// @return tokenAmount The cumulative unclaimed reward amount.
    /// @return newNextClaimRound The next reward round this staker has not yet resolved.
    function _claimRewardsFor(
        address hook,
        uint256 groupId,
        uint256 tokenId,
        IERC20 token,
        uint256 firstRound,
        uint256 lastRound
    )
        internal
        returns (uint256 tokenAmount, uint256 newNextClaimRound)
    {
        newNextClaimRound = lastRound + 1;

        // Walk every unclaimed historical round. The caller bounds this to completed rounds only.
        for (uint256 rewardRoundNumber = firstRound; rewardRoundNumber <= lastRound;) {
            // Load this round's reward data for JBX, the default group, and the reward token.
            JBRewardRoundData storage rewardRound = rewardRoundOf[hook][groupId][token][rewardRoundNumber];

            // Skip rounds that never received funding.
            if (rewardRound.amount != 0) {
                // Expired rounds forfeit unmaterialized inventory into the current active-voter set.
                if (_rewardRoundExpired(rewardRound)) {
                    _recycleExpiredRewardRound({hook: hook, groupId: groupId, token: token, round: rewardRoundNumber});
                } else {
                    // Live rounds can still be materialized by snapshot voters into fresh vesting entries.
                    tokenAmount += _claimRewardRoundFor({hook: hook, tokenId: tokenId, rewardRound: rewardRound});
                }
            }

            unchecked {
                ++rewardRoundNumber;
            }
        }
    }

    //*********************************************************************//
    // ----------------------- internal views ---------------------------- //
    //*********************************************************************//

    /// @notice Check if the account matches the staker address encoded in the token ID.
    /// @param hook Unused, because access is determined by the token ID encoding.
    /// @param tokenId The encoded staker address.
    /// @param account The account to check.
    /// @return canClaim True if the account matches the encoded address.
    function _canClaim(address hook, uint256 tokenId, address account) internal pure override returns (bool canClaim) {
        hook;
        canClaim = _claimBeneficiaryOf({hook: hook, tokenId: tokenId}) == account;
    }

    /// @notice The encoded staker address that receives permissionless collections.
    /// @param hook Unused, because the beneficiary is determined by the token ID encoding.
    /// @param tokenId The encoded staker address.
    /// @return beneficiary The staker address encoded in `tokenId`.
    function _claimBeneficiaryOf(address hook, uint256 tokenId) internal pure override returns (address beneficiary) {
        hook;
        if (tokenId >> 160 != 0) revert JBXDistributor_InvalidTokenId({tokenId: tokenId});

        // The high bits were checked above, so this cast recovers the encoded address.
        // forge-lint: disable-next-line(unsafe-typecast)
        beneficiary = address(uint160(tokenId));
    }

    /// @notice Revert unless the caller controls each encoded staker address.
    /// @param hook The configured JBX token.
    /// @param tokenIds The encoded staker addresses to check.
    function _requireCanClaimTokenIds(address hook, uint256[] calldata tokenIds) internal view override {
        // Each tokenId is an encoded address, so every requested claim must belong to msg.sender.
        for (uint256 i; i < tokenIds.length;) {
            if (!_canClaim({hook: hook, tokenId: tokenIds[i], account: msg.sender})) {
                revert JBDistributor_NoAccess({hook: hook, tokenId: tokenIds[i], account: msg.sender});
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice JBX staker IDs are encoded addresses, so they cannot be burned.
    /// @param hook Unused.
    /// @param tokenId Unused.
    /// @return tokenWasBurned Always false.
    function _tokenBurned(address hook, uint256 tokenId) internal pure override returns (bool tokenWasBurned) {
        hook;
        tokenId;
        tokenWasBurned = false;
    }

    /// @notice The delegated voting power of a staker at the current round's snapshot block.
    /// @param hook The configured JBX token.
    /// @param tokenId The encoded staker address.
    /// @return tokenStakeAmount The delegated voting power at the round's snapshot block.
    function _tokenStake(address hook, uint256 tokenId) internal view override returns (uint256 tokenStakeAmount) {
        tokenStakeAmount =
            _tokenStakeAt({hook: hook, tokenId: tokenId, blockNumber: roundSnapshotBlock[currentRound()]});
    }

    /// @notice The delegated voting power of a staker at an explicit snapshot block.
    /// @param hook The configured JBX token.
    /// @param tokenId The encoded staker address.
    /// @param blockNumber The historical block to query.
    /// @return tokenStakeAmount The delegated voting power at `blockNumber`.
    function _tokenStakeAt(
        address hook,
        uint256 tokenId,
        uint256 blockNumber
    )
        internal
        view
        returns (uint256 tokenStakeAmount)
    {
        if (tokenId >> 160 != 0) revert JBXDistributor_InvalidTokenId({tokenId: tokenId});

        // The high bits were checked above, so this cast recovers the encoded staker address.
        // forge-lint: disable-next-line(unsafe-typecast)
        address account = address(uint160(tokenId));

        // JBX rewards use the staker's real snapshot voting power; the delegate address does not receive rewards.
        tokenStakeAmount = IVotes(hook).getPastVotes({account: account, timepoint: blockNumber});
    }

    /// @notice The active-vote denominator recorded when a JBX reward round is first funded.
    /// @param hook The configured JBX token.
    /// @param groupId The reward group (unused because JBX rewards use the default group).
    /// @param blockNumber The block number to get the active total at.
    /// @return totalStakedAmount The stake denominator to record for the funded round.
    function _totalStake(
        address hook,
        uint256 groupId,
        uint256 blockNumber
    )
        internal
        view
        override
        returns (uint256 totalStakedAmount)
    {
        groupId;

        // Only balances delegated to nonzero delegates at the snapshot block share rewards.
        totalStakedAmount = IJBActiveVotes(hook).getPastTotalActiveVotes(blockNumber);
    }

    /// @notice Revert unless every token ID can be decoded as a staker address.
    /// @param hook The configured JBX token.
    /// @param tokenIds The encoded staker addresses to validate.
    function _validateTokenIds(address hook, uint256[] calldata tokenIds) internal pure override {
        hook;

        // Permissionless helpers can start vesting for any valid encoded staker slot.
        for (uint256 i; i < tokenIds.length;) {
            _claimBeneficiaryOf({hook: hook, tokenId: tokenIds[i]});

            unchecked {
                ++i;
            }
        }
    }

    //*********************************************************************//
    // ----------------------- private helpers --------------------------- //
    //*********************************************************************//

    /// @notice Returns the configured JBX address, reverting if it has not been set.
    /// @return jbx The configured JBX token address.
    function _jbxAddress() private view returns (address jbx) {
        jbx = address(JBX);
        if (jbx == address(0)) revert JBXDistributor_JBXNotSet();
    }

    /// @notice Return a project's ERC-20 token, reverting if the project has not deployed one.
    /// @param projectId The project whose token should be returned.
    /// @return token The project token.
    function _projectTokenOf(uint256 projectId) private view returns (IERC20 token) {
        IJBToken projectToken = TOKENS.tokenOf(projectId);
        if (address(projectToken) == address(0)) revert JBXDistributor_ZeroProjectToken({projectId: projectId});

        token = IERC20(address(projectToken));
    }

    /// @notice Revert unless `hook` is the configured JBX token.
    /// @param hook The hook argument supplied through the inherited API.
    function _requireJBXHook(address hook) private view {
        address jbx = _jbxAddress();
        if (hook != jbx) revert JBXDistributor_OnlyJBX({hook: hook, jbx: jbx});
    }

    /// @notice Revert unless `sucker` is registered for the mainnet project and peers to the origin chain.
    /// @param mainnetProjectId The mainnet project whose token rewards are being settled.
    /// @param originChainId The chain that prepared the bridge.
    /// @param sucker The sucker to check.
    function _requireOriginSucker(uint256 mainnetProjectId, uint256 originChainId, IJBSucker sucker) private view {
        if (!SUCKER_REGISTRY.isSuckerOf({projectId: mainnetProjectId, addr: address(sucker)})) {
            revert JBXDistributor_NotASucker({projectId: mainnetProjectId, sucker: address(sucker)});
        }

        uint256 suckerProjectId = sucker.projectId();
        if (suckerProjectId != mainnetProjectId) {
            revert JBXDistributor_SuckerProjectMismatch({projectId: mainnetProjectId, suckerProjectId: suckerProjectId});
        }

        uint256 peerChainId = sucker.peerChainId();
        if (peerChainId != originChainId) {
            revert JBXDistributor_SuckerPeerMismatch({expectedChainId: originChainId, actualChainId: peerChainId});
        }
    }

    /// @notice Revert unless `sucker` is a registered, sending-enabled sucker for `projectId` that peers to mainnet.
    /// @param projectId The project whose sucker is being checked.
    /// @param sucker The sucker to check.
    function _requireMainnetSucker(uint256 projectId, IJBSucker sucker) private view {
        if (!SUCKER_REGISTRY.isSuckerOf({projectId: projectId, addr: address(sucker)})) {
            revert JBXDistributor_NotASucker({projectId: projectId, sucker: address(sucker)});
        }

        uint256 suckerProjectId = sucker.projectId();
        if (suckerProjectId != projectId) {
            revert JBXDistributor_SuckerProjectMismatch({projectId: projectId, suckerProjectId: suckerProjectId});
        }

        uint256 peerChainId = sucker.peerChainId();
        if (peerChainId != MAINNET_CHAIN_ID) {
            revert JBXDistributor_SuckerPeerMismatch({expectedChainId: MAINNET_CHAIN_ID, actualChainId: peerChainId});
        }

        JBSuckerState state = sucker.state();
        if (state != JBSuckerState.ENABLED && state != JBSuckerState.DEPRECATION_PENDING) {
            revert JBXDistributor_SuckerNotSending({sucker: address(sucker), state: state});
        }
    }

    /// @notice Revert unless the split hook caller is a terminal or controller for the split project.
    /// @param context The split hook context.
    function _requireSplitCaller(JBSplitHookContext calldata context) private view {
        bool terminal = DIRECTORY.isTerminalOf({projectId: context.projectId, terminal: IJBTerminal(msg.sender)});
        bool controller = DIRECTORY.controllerOf(context.projectId) == IERC165(msg.sender);
        if (!terminal && !controller) {
            revert JBXDistributor_Unauthorized({projectId: context.projectId, caller: msg.sender});
        }
    }

    /// @notice Left-pad an EVM address into a 32-byte beneficiary identifier for sucker leaves.
    /// @param addr The address to encode.
    /// @return encoded The left-padded address.
    function _toBytes32(address addr) private pure returns (bytes32 encoded) {
        encoded = bytes32(uint256(uint160(addr)));
    }
}
