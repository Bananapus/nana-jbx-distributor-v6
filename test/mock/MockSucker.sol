// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {JBSuckerState} from "@bananapus/suckers-v6/src/enums/JBSuckerState.sol";
import {JBClaim} from "@bananapus/suckers-v6/src/structs/JBClaim.sol";

import {MockJBToken} from "./MockJBToken.sol";

/// @notice Sucker mock that records outbound prepares and mints claimed project tokens to leaf beneficiaries.
contract MockSucker {
    using SafeERC20 for IERC20;

    /// @notice The terminal token from the most recent `prepare`.
    address public lastTerminalToken;

    /// @notice The beneficiary from the most recent `prepare`.
    bytes32 public lastBeneficiary;

    /// @notice The metadata from the most recent `prepare`.
    bytes32 public lastMetadata;

    /// @notice The minimum terminal-token amount from the most recent `prepare`.
    uint256 public lastMinTokensReclaimed;

    /// @notice The project-token count from the most recent `prepare`.
    uint256 public lastProjectTokenCount;

    /// @notice The peer chain ID this mock sucker sends to.
    uint256 public peerChainId;

    /// @notice The project ID this mock sucker belongs to.
    uint256 public projectId;

    /// @notice The project token pulled by `prepare`.
    IERC20 public projectToken;

    /// @notice The destination project token minted by `claim`.
    MockJBToken public rewardToken;

    /// @notice The current sucker state.
    JBSuckerState public state;

    /// @notice The executed-leaf hashes stored by terminal token and leaf index.
    /// @custom:param token The terminal token of the executed leaf.
    /// @custom:param index The leaf index.
    mapping(address token => mapping(uint256 index => bytes32 hash)) public executedLeafHashOf;

    /// @notice Initialize the mock sucker.
    /// @param initialProjectId The project ID the sucker belongs to.
    /// @param initialPeerChainId The peer chain ID.
    /// @param initialProjectToken The source project token pulled during `prepare`.
    /// @param initialRewardToken The destination project token minted during `claim`.
    constructor(
        uint256 initialProjectId,
        uint256 initialPeerChainId,
        IERC20 initialProjectToken,
        MockJBToken initialRewardToken
    ) {
        projectId = initialProjectId;
        peerChainId = initialPeerChainId;
        projectToken = initialProjectToken;
        rewardToken = initialRewardToken;
        state = JBSuckerState.ENABLED;
    }

    /// @notice Claim a bridged leaf by minting destination project tokens to its beneficiary.
    /// @param claimData The claim to execute.
    function claim(JBClaim calldata claimData) external {
        address beneficiary = address(uint160(uint256(claimData.leaf.beneficiary)));

        // Store the same leaf hash shape the production sucker exposes for front-run authentication.
        executedLeafHashOf[claimData.token][claimData.leaf.index] = keccak256(
            abi.encodePacked(
                claimData.leaf.projectTokenCount,
                claimData.leaf.terminalTokenAmount,
                claimData.leaf.beneficiary,
                claimData.leaf.metadata
            )
        );

        rewardToken.mint({account: beneficiary, amount: claimData.leaf.projectTokenCount});
    }

    /// @notice Claim multiple bridged leaves.
    /// @param claims The claims to execute.
    function claim(JBClaim[] calldata claims) external {
        for (uint256 i; i < claims.length;) {
            this.claim(claims[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Record a bridge prepare and pull project tokens from the caller.
    /// @param projectTokenCount The number of project tokens to bridge.
    /// @param beneficiary The mainnet beneficiary.
    /// @param minTokensReclaimed The minimum terminal tokens to reclaim.
    /// @param token The terminal token to cash out into.
    /// @param metadata The metadata written into the sucker leaf.
    function prepare(
        uint256 projectTokenCount,
        bytes32 beneficiary,
        uint256 minTokensReclaimed,
        address token,
        bytes32 metadata
    )
        external
    {
        lastProjectTokenCount = projectTokenCount;
        lastBeneficiary = beneficiary;
        lastMinTokensReclaimed = minTokensReclaimed;
        lastTerminalToken = token;
        lastMetadata = metadata;

        projectToken.safeTransferFrom({from: msg.sender, to: address(this), value: projectTokenCount});
    }

    /// @notice Set the stored executed-leaf hash for a leaf.
    /// @param token The terminal token of the leaf.
    /// @param index The leaf index.
    /// @param hash The hash to store.
    function setExecutedLeafHashOf(address token, uint256 index, bytes32 hash) external {
        executedLeafHashOf[token][index] = hash;
    }

    /// @notice Set the sucker state.
    /// @param newState The state to set.
    function setState(JBSuckerState newState) external {
        state = newState;
    }
}
