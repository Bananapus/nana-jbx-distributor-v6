// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IJBActiveVotes} from "@bananapus/core-v6/src/interfaces/IJBActiveVotes.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBToken} from "@bananapus/core-v6/src/interfaces/IJBToken.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {JBXDistributor} from "../../src/JBXDistributor.sol";
import {IREVLoans} from "../../src/interfaces/IREVLoans.sol";
import {IREVOwner} from "../../src/interfaces/IREVOwner.sol";
import {MockDirectory} from "../mock/MockDirectory.sol";
import {MockJBToken} from "../mock/MockJBToken.sol";
import {MockJBX} from "../mock/MockJBX.sol";
import {MockSuckerRegistry} from "../mock/MockSuckerRegistry.sol";
import {MockTokens} from "../mock/MockTokens.sol";

/// @notice Randomly sequences split-funding / vest / collect / time-warp operations against a mainnet
/// `JBXDistributor` with a single reward token and two encoded JBX stakers.
/// @dev The handler is registered as the project's terminal so it can call `processSplitWith` (the only funding
/// path; direct `fund` always reverts). Before each fund it configures the round's `block.number - 1` snapshot so
/// the two stakers split the round pro-rata by their checkpointed active votes.
contract JBXDistributorHandler is Test {
    /// @notice The distributor under test.
    JBXDistributor public distributor;

    /// @notice The JBX active-votes token (the configured hook).
    MockJBX public jbx;

    /// @notice The ERC-20 reward token funded into mainnet rounds.
    MockJBToken public reward;

    /// @notice The project ID whose terminal this handler stands in for.
    uint256 public projectId;

    /// @notice The first encoded JBX staker address.
    address public alice;

    /// @notice The second encoded JBX staker address.
    address public bob;

    /// @notice The round duration mirrored from the distributor.
    uint256 public constant ROUND_DURATION = 1 days;

    /// @notice Cumulative reward tokens funded into the distributor through split hooks.
    uint256 public ghost_totalFunded;

    /// @notice Cumulative reward tokens collected by Alice.
    uint256 public ghost_collectedAlice;

    /// @notice Cumulative reward tokens collected by Bob.
    uint256 public ghost_collectedBob;

    /// @notice The last round a staker began vesting in, to avoid a same-round double-vest no-op.
    /// @custom:param tokenId The encoded staker address.
    mapping(uint256 tokenId => uint256 lastVestRound) public lastVestedRoundOf;

    /// @notice Whether a block's vote checkpoints have already been frozen.
    /// @dev A real IVotes token has immutable historical checkpoints, so a later fund in the same round must reuse
    /// the snapshot already locked for that block rather than rewriting a staker's numerator above the recorded
    /// round denominator.
    /// @custom:param blockNumber The snapshot block.
    mapping(uint256 blockNumber => bool frozen) public snapshotFrozenAt;

    /// @notice Initialize the handler with the fixture wiring.
    /// @param distributor_ The distributor under test.
    /// @param jbx_ The JBX active-votes token.
    /// @param reward_ The ERC-20 reward token.
    /// @param projectId_ The project ID this handler funds as.
    /// @param alice_ The first staker address.
    /// @param bob_ The second staker address.
    constructor(
        JBXDistributor distributor_,
        MockJBX jbx_,
        MockJBToken reward_,
        uint256 projectId_,
        address alice_,
        address bob_
    ) {
        distributor = distributor_;
        jbx = jbx_;
        reward = reward_;
        projectId = projectId_;
        alice = alice_;
        bob = bob_;
    }

    /// @notice The encoded staker token ID for an address.
    /// @param staker The staker address.
    /// @return tokenId The encoded token ID.
    function _tokenId(address staker) internal pure returns (uint256 tokenId) {
        tokenId = uint256(uint160(staker));
    }

    /// @notice Fund the current JBX reward round with a bounded amount through the split hook.
    /// @param rawAmount The fuzzed nominal amount.
    /// @param aliceVotes The fuzzed active votes for Alice at the round snapshot.
    /// @param bobVotes The fuzzed active votes for Bob at the round snapshot.
    function fund(uint96 rawAmount, uint96 aliceVotes, uint96 bobVotes) external {
        uint256 amount = bound(rawAmount, 0.001 ether, 50 ether);

        // The round's snapshot block is locked at `block.number - 1` on its first funding. Freeze that block's
        // checkpoints exactly once so a later fund in the same round cannot rewrite a staker's numerator above the
        // round denominator already recorded from it — matching a real IVotes token's immutable history.
        uint256 snapshotBlock = block.number - 1;
        if (!snapshotFrozenAt[snapshotBlock]) {
            uint256 av = bound(aliceVotes, 0, 1000 ether);
            uint256 bv = bound(bobVotes, 0, 1000 ether);
            jbx.setPastVotes({account: alice, blockNumber: snapshotBlock, votes: av});
            jbx.setPastVotes({account: bob, blockNumber: snapshotBlock, votes: bv});
            jbx.setPastTotalActiveVotes({blockNumber: snapshotBlock, activeVotes: av + bv});
            snapshotFrozenAt[snapshotBlock] = true;
        }

        reward.mint({account: address(this), amount: amount});
        reward.approve({spender: address(distributor), value: amount});

        // The handler is the registered terminal, so this split-hook call is authorized.
        distributor.processSplitWith(_context(amount));
        ghost_totalFunded += amount;
    }

    /// @notice Advance time by 0..3 rounds and roll the block so the next snapshot is strictly in the past.
    /// @param rawRounds The fuzzed number of rounds to advance.
    function warp(uint8 rawRounds) external {
        uint256 rounds = bound(rawRounds, 0, 3);
        if (rounds != 0) {
            vm.warp(block.timestamp + ROUND_DURATION * rounds);
            vm.roll(block.number + 1);
        }
    }

    /// @notice Begin vesting for one staker (skipping a same-round repeat that would be a no-op).
    /// @param whichAlice True to act for Alice, false for Bob.
    function beginVesting(bool whichAlice) external {
        address staker = whichAlice ? alice : bob;
        uint256 round = distributor.currentRound();
        if (lastVestedRoundOf[_tokenId(staker)] == round) return;

        uint256[] memory ids = new uint256[](1);
        ids[0] = _tokenId(staker);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(reward));

        vm.prank(staker);
        distributor.beginVesting({tokenIds: ids, tokens: tokens});
        lastVestedRoundOf[_tokenId(staker)] = round;
    }

    /// @notice Collect vested rewards for one staker to their own address.
    /// @param whichAlice True to act for Alice, false for Bob.
    function collect(bool whichAlice) external {
        address staker = whichAlice ? alice : bob;
        uint256[] memory ids = new uint256[](1);
        ids[0] = _tokenId(staker);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(reward));

        uint256 balanceBefore = reward.balanceOf(staker);
        vm.prank(staker);
        distributor.collectVestedRewards({hook: address(jbx), tokenIds: ids, tokens: tokens, beneficiary: staker});
        uint256 gained = reward.balanceOf(staker) - balanceBefore;

        if (whichAlice) ghost_collectedAlice += gained;
        else ghost_collectedBob += gained;
    }

    /// @notice Build a mainnet ERC-20 split hook context for the reward token.
    /// @param amount The split amount.
    /// @return context The split hook context.
    function _context(uint256 amount) internal view returns (JBSplitHookContext memory context) {
        context = JBSplitHookContext({
            token: address(reward),
            amount: amount,
            decimals: 18,
            projectId: projectId,
            groupId: uint256(uint160(address(reward))),
            split: JBSplit({
                percent: 0,
                projectId: 0,
                beneficiary: payable(address(0)),
                preferAddToBalance: false,
                lockedUntil: 0,
                hook: IJBSplitHook(address(distributor))
            })
        });
    }
}

/// @notice Stateful functional-correctness invariants for `JBXDistributor` on mainnet (split-funding path,
/// IJBActiveVotes snapshot denominator). Asserts the conservation, no-overclaim, and
/// `totalVestingAmountOf == sum of claimedFor` properties from INVARIANTS.md ("Reward Rounds",
/// "Vesting And Collection").
contract JBXDistributorInvariant is StdInvariant, Test {
    JBXDistributor internal _distributor;
    MockDirectory internal _directory;
    MockJBX internal _jbx;
    MockJBToken internal _reward;
    MockTokens internal _tokens;
    MockSuckerRegistry internal _suckerRegistry;
    JBXDistributorHandler internal _handler;

    address internal _alice = makeAddr("inv_alice");
    address internal _bob = makeAddr("inv_bob");

    uint256 internal constant _MAINNET_CHAIN_ID = 1;
    uint256 internal constant _PROJECT_ID = 7;
    uint256 internal constant _ROUND_DURATION = 1 days;

    function setUp() public {
        vm.chainId(_MAINNET_CHAIN_ID);
        vm.roll(100);
        vm.warp(10_000);

        _directory = new MockDirectory();
        _jbx = new MockJBX();
        _tokens = new MockTokens();
        _suckerRegistry = new MockSuckerRegistry();
        _reward = new MockJBToken({name: "Reward", symbol: "RWD"});

        // A no-expiry distributor keeps every funded round claimable, so recycling cannot move rewards out from
        // under the conservation checks. Vesting over four rounds exercises the partial-unlock collection path.
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
            initialVestingRounds: 4,
            initialClaimDuration: 0
        });
        _distributor.setJBX({jbx: IJBActiveVotes(address(_jbx))});

        _handler = new JBXDistributorHandler({
            distributor_: _distributor,
            jbx_: _jbx,
            reward_: _reward,
            projectId_: _PROJECT_ID,
            alice_: _alice,
            bob_: _bob
        });

        // Authorize the handler as the project's terminal so its split-hook funding is accepted.
        _directory.setIsTerminalOf({projectId: _PROJECT_ID, terminal: IJBTerminal(address(_handler)), isTerminal: true});

        targetContract(address(_handler));
    }

    /// @notice The distributor's tracked balance for JBX equals its real ERC-20 holdings. One hook, one ERC-20, no
    /// loans => funding credits both and owner collections debit both in lockstep, after every randomized sequence.
    function invariant_trackedBalanceMatchesActualBacking() public view {
        assertEq(
            _distributor.balanceOf(address(_jbx), IERC20(address(_reward))),
            _reward.balanceOf(address(_distributor)),
            "tracked balance != actual backing"
        );
    }

    /// @notice No-overclaim: total reward tokens collected by all stakers never exceeds total funded.
    function invariant_totalCollectedNeverExceedsFunded() public view {
        assertLe(
            _handler.ghost_collectedAlice() + _handler.ghost_collectedBob(),
            _handler.ghost_totalFunded(),
            "collected exceeds funded"
        );
    }

    /// @notice The aggregate vesting counter equals the sum of each staker's remaining uncollected claims.
    function invariant_totalVestingMatchesRemainingClaims() public view {
        IERC20 token = IERC20(address(_reward));
        uint256 remaining = _distributor.claimedFor(address(_jbx), uint256(uint160(_alice)), token)
            + _distributor.claimedFor(address(_jbx), uint256(uint160(_bob)), token);
        assertEq(_distributor.totalVestingAmountOf(address(_jbx), token), remaining, "vesting != sum claimedFor");
    }

    /// @notice `totalVestingAmountOf` never exceeds the hook's tracked balance (can't owe more than is held).
    function invariant_vestingNeverExceedsBalance() public view {
        assertLe(
            _distributor.totalVestingAmountOf(address(_jbx), IERC20(address(_reward))),
            _distributor.balanceOf(address(_jbx), IERC20(address(_reward))),
            "vesting exceeds balance"
        );
    }

    /// @notice `collectableFor` (unlocked) never exceeds `claimedFor` (vesting + unlocked) for either staker.
    function invariant_collectableNeverExceedsClaimed() public view {
        IERC20 token = IERC20(address(_reward));
        assertLe(
            _distributor.collectableFor(address(_jbx), uint256(uint160(_alice)), token),
            _distributor.claimedFor(address(_jbx), uint256(uint160(_alice)), token),
            "alice collectable > claimed"
        );
        assertLe(
            _distributor.collectableFor(address(_jbx), uint256(uint160(_bob)), token),
            _distributor.claimedFor(address(_jbx), uint256(uint160(_bob)), token),
            "bob collectable > claimed"
        );
    }

    /// @notice Whole-system token conservation: funded supply is split among the distributor, the stakers, and the
    /// handler (the funder of record).
    function invariant_balanceConservation() public view {
        uint256 total = _reward.totalSupply();
        uint256 acc = _reward.balanceOf(address(_distributor)) + _reward.balanceOf(_alice) + _reward.balanceOf(_bob)
            + _reward.balanceOf(address(_handler));
        assertEq(acc, total, "token conservation broken");
    }
}
