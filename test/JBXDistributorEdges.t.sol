// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IJBActiveVotes} from "@bananapus/core-v6/src/interfaces/IJBActiveVotes.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBToken} from "@bananapus/core-v6/src/interfaces/IJBToken.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBClaim} from "@bananapus/suckers-v6/src/structs/JBClaim.sol";
import {JBLeaf} from "@bananapus/suckers-v6/src/structs/JBLeaf.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {JBXDistributor} from "../src/JBXDistributor.sol";
import {IREVLoans} from "../src/interfaces/IREVLoans.sol";
import {IREVOwner} from "../src/interfaces/IREVOwner.sol";
import {MockDirectory} from "./mock/MockDirectory.sol";
import {MockFeeOnTransferToken} from "./mock/MockFeeOnTransferToken.sol";
import {MockJBToken} from "./mock/MockJBToken.sol";
import {MockJBX} from "./mock/MockJBX.sol";
import {MockSuckerRegistry} from "./mock/MockSuckerRegistry.sol";
import {MockTokens} from "./mock/MockTokens.sol";

/// @notice Edge-case unit tests for the JBX distributor: configuration guards, split-caller authorization,
/// leaf-metadata bounds, fee-on-transfer crediting, chain-scoping guards, and expiry recycling.
contract JBXDistributorEdgesTest is Test {
    /// @notice A non-terminal caller used to prove split authorization.
    address internal constant _STRANGER = address(0x5723A6E2);

    /// @notice The configured mainnet chain ID.
    uint256 internal constant _MAINNET_CHAIN_ID = 1;

    /// @notice A project ID used in split and bridge tests.
    uint256 internal constant _PROJECT_ID = 7;

    /// @notice The round duration used by the test distributor.
    uint256 internal constant _ROUND_DURATION = 1 days;

    /// @notice The claim duration used by the test distributor.
    uint48 internal constant _CLAIM_DURATION = 2 days;

    /// @notice The distributor under test.
    JBXDistributor internal _distributor;

    /// @notice Mock directory that authorizes split callers.
    MockDirectory internal _directory;

    /// @notice Mock JBX token used as the active-vote staking token.
    MockJBX internal _jbx;

    /// @notice Mock token registry that resolves project tokens.
    MockTokens internal _tokens;

    /// @notice Mock sucker registry that authorizes project suckers.
    MockSuckerRegistry internal _suckerRegistry;

    /// @notice Reward token accepted on mainnet split funding.
    MockJBToken internal _rewardToken;

    /// @notice Source project token accepted on remote split funding.
    MockJBToken internal _projectToken;

    /// @notice Deploy a fresh mainnet distributor fixture with JBX configured.
    function setUp() external {
        vm.chainId(_MAINNET_CHAIN_ID);
        vm.roll(100);
        vm.warp(10_000);

        _directory = new MockDirectory();
        _jbx = new MockJBX();
        _tokens = new MockTokens();
        _suckerRegistry = new MockSuckerRegistry();
        _rewardToken = new MockJBToken({name: "Reward", symbol: "RWD"});
        _projectToken = new MockJBToken({name: "Project", symbol: "PRJ"});

        _tokens.setTokenFor({projectId: _PROJECT_ID, token: IJBToken(address(_projectToken))});
        _directory.setIsTerminalOf({projectId: _PROJECT_ID, terminal: IJBTerminal(address(this)), isTerminal: true});

        _distributor = new JBXDistributor({
            directory: IJBDirectory(address(_directory)),
            controller: IJBController(address(0)),
            tokens: IJBTokens(address(_tokens)),
            suckerRegistry: IJBSuckerRegistry(address(_suckerRegistry)),
            revLoans: IREVLoans(address(0)),
            revOwner: IREVOwner(address(0)),
            owner: address(this),
            mainnetChainId: _MAINNET_CHAIN_ID,
            initialRoundDuration: _ROUND_DURATION,
            initialVestingRounds: 1,
            initialClaimDuration: _CLAIM_DURATION
        });

        _distributor.setJBX({jbx: IJBActiveVotes(address(_jbx))});
    }

    /// @notice `setJBX` rejects the zero address so the reward constituency can never be left pointing at nothing.
    function test_setJBX_revertsOnZero() external {
        JBXDistributor unset = new JBXDistributor({
            directory: IJBDirectory(address(_directory)),
            controller: IJBController(address(0)),
            tokens: IJBTokens(address(_tokens)),
            suckerRegistry: IJBSuckerRegistry(address(_suckerRegistry)),
            revLoans: IREVLoans(address(0)),
            revOwner: IREVOwner(address(0)),
            owner: address(this),
            mainnetChainId: _MAINNET_CHAIN_ID,
            initialRoundDuration: _ROUND_DURATION,
            initialVestingRounds: 1,
            initialClaimDuration: _CLAIM_DURATION
        });

        vm.expectRevert(JBXDistributor.JBXDistributor_ZeroJBX.selector);
        unset.setJBX({jbx: IJBActiveVotes(address(0))});
    }

    /// @notice Split funding rejects callers that are neither a terminal nor controller for the split's project.
    function test_processSplitWith_revertsOnUnauthorizedCaller() external {
        uint256 amount = 1 ether;
        _rewardToken.mint({account: _STRANGER, amount: amount});

        vm.startPrank(_STRANGER);
        _rewardToken.approve({spender: address(_distributor), value: amount});
        vm.expectRevert(
            abi.encodeWithSelector(JBXDistributor.JBXDistributor_Unauthorized.selector, _PROJECT_ID, _STRANGER)
        );
        _distributor.processSplitWith(_context({token: address(_rewardToken), amount: amount}));
        vm.stopPrank();
    }

    /// @notice An ERC-20 split must not carry native ETH.
    function test_processSplitWith_revertsOnErc20WithNativeValue() external {
        uint256 amount = 1 ether;
        _rewardToken.mint({account: address(this), amount: amount});
        _rewardToken.approve({spender: address(_distributor), value: amount});

        vm.deal(address(this), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                JBXDistributor.JBXDistributor_TokenMismatch.selector,
                address(_rewardToken),
                JBConstants.NATIVE_TOKEN,
                uint256(1)
            )
        );
        _distributor.processSplitWith{value: 1}(_context({token: address(_rewardToken), amount: amount}));
    }

    /// @notice Mainnet native splits must send a `msg.value` matching the context amount.
    function test_processSplitWith_revertsOnNativeAmountMismatch() external {
        vm.deal(address(this), 5 ether);

        vm.expectRevert(
            abi.encodeWithSelector(JBXDistributor.JBXDistributor_NativeAmountMismatch.selector, uint256(1), uint256(2))
        );
        _distributor.processSplitWith{value: 1}(_context({token: JBConstants.NATIVE_TOKEN, amount: 2}));
    }

    /// @notice Fee-on-transfer reward tokens are credited by the received balance delta, not the requested amount.
    function test_processSplitWith_creditsFeeOnTransferByDelta() external {
        MockFeeOnTransferToken fot = new MockFeeOnTransferToken({initialFeeBps: 1000}); // 10% transfer fee.

        uint256 snapshotBlock = block.number - 1;
        _jbx.setPastTotalActiveVotes({blockNumber: snapshotBlock, activeVotes: 1000 ether});

        uint256 requested = 100 ether;
        fot.mint({to: address(this), amount: requested});
        fot.approve({spender: address(_distributor), value: requested});

        _distributor.processSplitWith(_context({token: address(fot), amount: requested}));

        // The distributor only received 90% after the burn, and that is exactly what was recorded.
        uint256 expectedDelta = 90 ether;
        assertEq(fot.balanceOf(address(_distributor)), expectedDelta);
        assertEq(_distributor.balanceOf({hook: address(_jbx), token: IERC20(address(fot))}), expectedDelta);

        (uint208 roundAmount,,,,) =
            _distributor.rewardRoundOf({hook: address(_jbx), groupId: 0, token: IERC20(address(fot)), round: 0});
        assertEq(roundAmount, expectedDelta);
    }

    /// @notice `packLeafMetadata` rejects an origin chain ID wider than the packed field.
    function test_packLeafMetadata_revertsOnLargeChainId() external {
        uint256 tooLarge = uint256(type(uint32).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(JBXDistributor.JBXDistributor_ChainIdTooLarge.selector, tooLarge));
        _distributor.packLeafMetadata({originChainId: tooLarge, projectId: _PROJECT_ID});
    }

    /// @notice `packLeafMetadata` rejects a project ID wider than the packed field.
    function test_packLeafMetadata_revertsOnLargeProjectId() external {
        uint256 tooLarge = uint256(type(uint64).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(JBXDistributor.JBXDistributor_ProjectIdTooLarge.selector, tooLarge));
        _distributor.packLeafMetadata({originChainId: _MAINNET_CHAIN_ID, projectId: tooLarge});
    }

    /// @notice `bridgeToMainnet` is remote-only: it reverts on the configured mainnet chain.
    function test_bridgeToMainnet_revertsOnMainnet() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                JBXDistributor.JBXDistributor_RemoteOnly.selector, _MAINNET_CHAIN_ID, _MAINNET_CHAIN_ID
            )
        );
        _distributor.bridgeToMainnet({
            projectId: _PROJECT_ID,
            sucker: IJBSucker(address(0)),
            terminalToken: address(_rewardToken),
            amount: 1 ether,
            minTokensReclaimed: 0
        });
    }

    /// @notice `claimRemoteRewards` rejects an origin chain ID equal to mainnet (a leaf can only arrive from remote).
    function test_claimRemoteRewards_revertsOnMainnetOrigin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                JBXDistributor.JBXDistributor_MainnetOnly.selector, _MAINNET_CHAIN_ID, _MAINNET_CHAIN_ID
            )
        );
        _distributor.claimRemoteRewards({
            originChainId: _MAINNET_CHAIN_ID,
            originProjectId: _PROJECT_ID,
            mainnetProjectId: _PROJECT_ID,
            sucker: IJBSucker(address(0)),
            claimData: _emptyClaim()
        });
    }

    /// @notice Expiry recycling moves only the unclaimed remainder of an expired round into the current round.
    function test_recycleExpiredRewards_movesUnclaimedRemainderToCurrentRound() external {
        // Fund round 0 with no active voters so the entire pot stays unclaimable and is fully recyclable.
        uint256 amount = 500 ether;
        uint256 snapshotBlock = block.number - 1;
        _jbx.setPastTotalActiveVotes({blockNumber: snapshotBlock, activeVotes: 0});
        _rewardToken.mint({account: address(this), amount: amount});
        _rewardToken.approve({spender: address(_distributor), value: amount});
        _distributor.processSplitWith(_context({token: address(_rewardToken), amount: amount}));

        // Warp well past round 0's deadline so it is expired.
        vm.warp(block.timestamp + _ROUND_DURATION * 2 + _CLAIM_DURATION + 1);
        uint256 nowRound = _distributor.currentRound();

        uint256[] memory rounds = new uint256[](1);
        rounds[0] = 0;
        uint256 recycled = _distributor.recycleExpiredRewards({
            hook: address(_jbx), token: IERC20(address(_rewardToken)), rounds: rounds
        });

        // The full unclaimed pot moved into the current round; the contract still custodies the tokens.
        assertEq(recycled, amount);
        assertEq(_rewardToken.balanceOf(address(_distributor)), amount);

        (uint208 currentRoundAmount,,,,) = _distributor.rewardRoundOf({
            hook: address(_jbx), groupId: 0, token: IERC20(address(_rewardToken)), round: nowRound
        });
        assertEq(currentRoundAmount, amount);
    }

    /// @notice A zero-stake round (unclaimable forever) is recyclable even BEFORE its claim deadline — otherwise its
    /// funds would be stranded permanently under a never-expiring (`CLAIM_DURATION == 0`) configuration.
    function test_recycleExpiredRewards_zeroStakeRoundRecyclesBeforeExpiry() external {
        // Fund round 0 with zero active votes so the pot can never be claimed.
        uint256 amount = 500 ether;
        uint256 snapshotBlock = block.number - 1;
        _jbx.setPastTotalActiveVotes({blockNumber: snapshotBlock, activeVotes: 0});
        _rewardToken.mint({account: address(this), amount: amount});
        _rewardToken.approve({spender: address(_distributor), value: amount});
        _distributor.processSplitWith(_context({token: address(_rewardToken), amount: amount}));

        // Advance into round 1 but stay BEFORE round 0's claim deadline (CLAIM_DURATION = 2 days), so the round is
        // unclaimable AND not yet expired.
        vm.warp(_distributor.roundStartTimestamp(1) + 1);
        uint256 nowRound = _distributor.currentRound();
        assertGt(nowRound, 0, "advanced past round 0");

        (,,, uint48 claimDeadline, uint208 totalStake) = _distributor.rewardRoundOf({
            hook: address(_jbx), groupId: 0, token: IERC20(address(_rewardToken)), round: 0
        });
        assertEq(totalStake, 0, "round 0 has zero stake");
        // forge-lint: disable-next-line(block-timestamp)
        assertGt(claimDeadline, block.timestamp, "round 0 is not yet expired");

        uint256[] memory rounds = new uint256[](1);
        rounds[0] = 0;
        uint256 recycled = _distributor.recycleExpiredRewards({
            hook: address(_jbx), token: IERC20(address(_rewardToken)), rounds: rounds
        });
        assertEq(recycled, amount, "zero-stake round recycled despite not being expired");

        (uint208 movedAmount,,,,) = _distributor.rewardRoundOf({
            hook: address(_jbx), groupId: 0, token: IERC20(address(_rewardToken)), round: nowRound
        });
        assertEq(movedAmount, amount, "funds moved to current round, not stranded");
    }

    /// @notice A zero-stake current round is unclaimable, but it must wait for a later round before recycling so the
    /// round cannot repeatedly recycle into itself and inflate raw accounting fields.
    function test_recycleExpiredRewards_zeroStakeCurrentRoundNoOps() external {
        uint256 amount = 500 ether;
        uint256 snapshotBlock = block.number - 1;
        _jbx.setPastTotalActiveVotes({blockNumber: snapshotBlock, activeVotes: 0});
        _rewardToken.mint({account: address(this), amount: amount});
        _rewardToken.approve({spender: address(_distributor), value: amount});
        _distributor.processSplitWith(_context({token: address(_rewardToken), amount: amount}));

        uint256 round = _distributor.currentRound();
        assertEq(round, 0, "funded round is still current");

        uint256[] memory rounds = new uint256[](1);
        rounds[0] = round;
        uint256 recycled = _distributor.recycleExpiredRewards({
            hook: address(_jbx), token: IERC20(address(_rewardToken)), rounds: rounds
        });
        assertEq(recycled, 0, "current round cannot recycle into itself");

        (uint208 recordedAmount,, uint208 claimedAmount,, uint208 totalStake) = _distributor.rewardRoundOf({
            hook: address(_jbx), groupId: 0, token: IERC20(address(_rewardToken)), round: round
        });
        assertEq(recordedAmount, amount, "amount did not inflate");
        assertEq(claimedAmount, 0, "round was not marked settled");
        assertEq(totalStake, 0, "round remains zero-stake");

        recycled = _distributor.recycleExpiredRewards({
            hook: address(_jbx), token: IERC20(address(_rewardToken)), rounds: rounds
        });
        assertEq(recycled, 0, "repeat current-round sweep is still a no-op");

        (recordedAmount,, claimedAmount,,) = _distributor.rewardRoundOf({
            hook: address(_jbx), groupId: 0, token: IERC20(address(_rewardToken)), round: round
        });
        assertEq(recordedAmount, amount, "repeat sweep did not inflate amount");
        assertEq(claimedAmount, 0, "repeat sweep did not inflate claimed amount");

        vm.warp(_distributor.roundStartTimestamp(1) + 1);
        uint256 nowRound = _distributor.currentRound();
        assertGt(nowRound, round, "advanced into a later round");

        recycled = _distributor.recycleExpiredRewards({
            hook: address(_jbx), token: IERC20(address(_rewardToken)), rounds: rounds
        });
        assertEq(recycled, amount, "zero-stake prior round still recycles forward");

        (,, claimedAmount,,) = _distributor.rewardRoundOf({
            hook: address(_jbx), groupId: 0, token: IERC20(address(_rewardToken)), round: round
        });
        (uint208 movedAmount,,,,) = _distributor.rewardRoundOf({
            hook: address(_jbx), groupId: 0, token: IERC20(address(_rewardToken)), round: nowRound
        });
        assertEq(claimedAmount, amount, "prior round settled after forward recycle");
        assertEq(movedAmount, amount, "later round receives recycled amount");
    }

    /// @notice Build a split hook context.
    /// @param token The token sent to the split hook.
    /// @param amount The split amount.
    /// @return context The split hook context.
    function _context(address token, uint256 amount) internal view returns (JBSplitHookContext memory context) {
        context = JBSplitHookContext({
            token: token,
            amount: amount,
            decimals: 18,
            projectId: _PROJECT_ID,
            groupId: token == JBConstants.NATIVE_TOKEN ? 1 : uint256(uint160(token)),
            split: JBSplit({
                percent: 0,
                projectId: 0,
                beneficiary: payable(address(0)),
                preferAddToBalance: false,
                lockedUntil: 0,
                hook: IJBSplitHook(address(_distributor))
            })
        });
    }

    /// @notice Build an empty sucker claim for guard tests that revert before the claim is read.
    /// @return claimData The empty claim data.
    function _emptyClaim() internal pure returns (JBClaim memory claimData) {
        bytes32[32] memory proof;
        claimData = JBClaim({
            token: address(0),
            leaf: JBLeaf({
                index: 0, beneficiary: bytes32(0), projectTokenCount: 0, terminalTokenAmount: 0, metadata: bytes32(0)
            }),
            proof: proof
        });
    }
}
