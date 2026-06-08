// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import {IJBActiveVotes} from "@bananapus/core-v6/src/interfaces/IJBActiveVotes.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {JBXDistributor} from "../../src/JBXDistributor.sol";
import {IREVLoans} from "../../src/interfaces/IREVLoans.sol";
import {IREVOwner} from "../../src/interfaces/IREVOwner.sol";
import {MockJBX} from "../mock/MockJBX.sol";

/// @notice Property proofs/fuzz for `JBXDistributor`'s tractable arithmetic and configuration guards.
///
/// Each property is split by SMT tractability:
///   * `check_<name>` — Halmos symbolic proofs for the leaf-metadata bit-packing (pure shifts/masks, no `mulDiv`)
///     and the bounded pro-rata floor-share comparison.
///   * `testFuzz_<name>` — forge fuzz for the full-domain pro-rata `mulDiv` (which Halmos cannot tractably explore)
///     and for the stateful one-shot `setJBX` / split-funding guards that require a deployed contract.
///
/// Spec references (INVARIANTS.md):
///   * "Reward Rounds"   — a round's pot is split pro-rata by checkpointed stake; floor shares never over-distribute.
///   * "Remote Bridge Queue" / "Mainnet Settlement" — leaf metadata is `packLeafMetadata(originChainId, projectId)`.
///   * "JBX Configuration" — JBX is unset until `setJBX` succeeds, rejects zero, and succeeds at most once.
contract JBXDistributorProperties is Test {
    /// @notice The configured mainnet chain ID for the deployed fixture.
    uint256 internal constant _MAINNET_CHAIN_ID = 1;

    /// @notice The round duration for the deployed fixture.
    uint256 internal constant _ROUND_DURATION = 1 days;

    /// @notice A standalone distributor used by the stateful guard properties.
    JBXDistributor internal _distributor;

    /// @notice Deploy a minimal mainnet distributor with no dependencies wired beyond what the guards exercise.
    function setUp() public {
        vm.chainId(_MAINNET_CHAIN_ID);
        _distributor = new JBXDistributor({
            directory: IJBDirectory(address(0)),
            controller: IJBController(address(0)),
            tokens: IJBTokens(address(0)),
            suckerRegistry: IJBSuckerRegistry(address(0)),
            revLoans: IREVLoans(address(0)),
            revOwner: IREVOwner(address(0)),
            owner: address(this),
            mainnetChainId: _MAINNET_CHAIN_ID,
            initialRoundDuration: _ROUND_DURATION,
            initialVestingRounds: 1,
            initialClaimDuration: 0
        });
    }

    //*********************************************************************//
    // ---------------- P1: leaf-metadata bit-packing -------------------- //
    //*********************************************************************//

    /// @notice HALMOS: packing then unpacking recovers both fields exactly, with no cross-field bleed. The layout
    /// is `bits[95:64] = originChainId`, `bits[63:0] = projectId`. Pure shifts/masks keep this SMT-tractable.
    /// @param originChainId An in-range origin chain ID (fits uint32).
    /// @param projectId An in-range project ID (fits uint64).
    function check_packLeafMetadataRoundtrip(uint32 originChainId, uint64 projectId) public view {
        bytes32 metadata =
            _distributor.packLeafMetadata({originChainId: uint256(originChainId), projectId: uint256(projectId)});

        uint256 packed = uint256(metadata);

        // The low 64 bits recover the project ID, the next 32 bits recover the origin chain ID. Mask in uint256
        // space (no truncating cast) so the comparison is over the full extracted field.
        assert(packed & type(uint64).max == uint256(projectId));
        assert((packed >> 64) & type(uint32).max == uint256(originChainId));

        // Bits above [95] are reserved and must stay clear.
        assert(packed >> 96 == 0);
    }

    /// @notice HALMOS: two distinct in-range `(originChainId, projectId)` pairs never collide on the same packed
    /// metadata, so a settled leaf cannot be confused with another chain/project's leaf.
    /// @param originA The first origin chain ID.
    /// @param projectA The first project ID.
    /// @param originB The second origin chain ID.
    /// @param projectB The second project ID.
    function check_packLeafMetadataInjective(
        uint32 originA,
        uint64 projectA,
        uint32 originB,
        uint64 projectB
    )
        public
        view
    {
        // Distinct pairs only.
        if (originA == originB && projectA == projectB) return;

        bytes32 a = _distributor.packLeafMetadata({originChainId: uint256(originA), projectId: uint256(projectA)});
        bytes32 b = _distributor.packLeafMetadata({originChainId: uint256(originB), projectId: uint256(projectB)});

        assert(a != b);
    }

    /// @notice FUZZ: full-domain roundtrip including the out-of-range reverts (origin > uint32, project > uint64).
    /// @param originChainId A full-width origin chain ID.
    /// @param projectId A full-width project ID.
    function testFuzz_packLeafMetadataRoundtrip(uint256 originChainId, uint256 projectId) public {
        if (originChainId > type(uint32).max) {
            vm.expectRevert(
                abi.encodeWithSelector(JBXDistributor.JBXDistributor_ChainIdTooLarge.selector, originChainId)
            );
            _distributor.packLeafMetadata({originChainId: originChainId, projectId: projectId});
            return;
        }
        if (projectId > type(uint64).max) {
            vm.expectRevert(abi.encodeWithSelector(JBXDistributor.JBXDistributor_ProjectIdTooLarge.selector, projectId));
            _distributor.packLeafMetadata({originChainId: originChainId, projectId: projectId});
            return;
        }

        bytes32 metadata = _distributor.packLeafMetadata({originChainId: originChainId, projectId: projectId});
        uint256 packed = uint256(metadata);

        // Mask each field in uint256 space (no truncating cast) and compare against the in-range inputs.
        assertEq(packed & type(uint64).max, projectId, "project field mismatch");
        assertEq((packed >> 64) & type(uint32).max, originChainId, "origin field mismatch");
        assertEq(packed >> 96, 0, "reserved bits set");
    }

    //*********************************************************************//
    // ----------------- P2: pro-rata never over-distributes -------------- //
    //*********************************************************************//

    // The symbolic boundary proofs for this property live in `JBXDistributorHalmos` (concrete tables that keep the
    // 512-bit `mulDiv` out of the solver). The full-domain `mulDiv` proof is fuzzed below, which Halmos cannot
    // tractably explore.

    /// @notice FUZZ: over the FULL `mulDiv` domain, the sum of every staker's floor share of a round (their stake
    /// over the round's total stake) never exceeds the round amount. Models how `_claimRewardRoundFor` allocates
    /// `mulDiv(rewardRound.amount, tokenStake, rewardRound.totalStake)` to each staker.
    /// @param amount The round reward amount.
    /// @param stakeA The first staker's stake.
    /// @param stakeB The second staker's stake.
    /// @param stakeC The third staker's stake.
    function testFuzz_proRataNeverOverDistributes(
        uint256 amount,
        uint256 stakeA,
        uint256 stakeB,
        uint256 stakeC
    )
        public
        pure
    {
        amount = bound(amount, 0, type(uint208).max);
        stakeA = bound(stakeA, 0, type(uint96).max);
        stakeB = bound(stakeB, 0, type(uint96).max);
        stakeC = bound(stakeC, 0, type(uint96).max);

        uint256 totalStake = stakeA + stakeB + stakeC;
        if (totalStake == 0) return; // empty-denominator rounds allocate nothing.

        uint256 shareA = mulDiv({x: amount, y: stakeA, denominator: totalStake});
        uint256 shareB = mulDiv({x: amount, y: stakeB, denominator: totalStake});
        uint256 shareC = mulDiv({x: amount, y: stakeC, denominator: totalStake});

        // A partition of stake floor-divides the pot without ever exceeding it (each share is also independently
        // bounded by the pot).
        assertLe(shareA, amount, "single share exceeds pot");
        assertLe(shareA + shareB + shareC, amount, "sum of shares exceeds pot");
    }

    /// @notice FUZZ: a staker holding all of the active stake claims the entire round amount (no value is stranded
    /// when a single voter is the whole denominator).
    /// @param amount The round reward amount.
    /// @param stake The sole staker's stake.
    function testFuzz_proRataSoleStakerTakesAll(uint256 amount, uint256 stake) public pure {
        amount = bound(amount, 0, type(uint208).max);
        stake = bound(stake, 1, type(uint128).max);

        uint256 share = mulDiv({x: amount, y: stake, denominator: stake});

        assertEq(share, amount, "sole staker did not receive full pot");
    }

    //*********************************************************************//
    // ------------------- P3: JBX one-shot configuration ----------------- //
    //*********************************************************************//

    /// @notice `setJBX` rejects the zero address, succeeds exactly once for any nonzero JBX, and reverts on every
    /// later attempt — so no split can redirect the reward constituency after setup.
    function test_setJBXOneShot() public {
        // Use freshly deployed mocks so each call has a real IJBActiveVotes implementation at a nonzero address.
        MockJBX first = new MockJBX();
        MockJBX second = new MockJBX();

        // A standalone, unconfigured distributor: JBX starts unset.
        JBXDistributor d = new JBXDistributor({
            directory: IJBDirectory(address(0)),
            controller: IJBController(address(0)),
            tokens: IJBTokens(address(0)),
            suckerRegistry: IJBSuckerRegistry(address(0)),
            revLoans: IREVLoans(address(0)),
            revOwner: IREVOwner(address(0)),
            owner: address(this),
            mainnetChainId: _MAINNET_CHAIN_ID,
            initialRoundDuration: _ROUND_DURATION,
            initialVestingRounds: 1,
            initialClaimDuration: 0
        });
        assertEq(address(d.JBX()), address(0), "JBX set before setJBX");

        // Zero address is rejected.
        vm.expectRevert(JBXDistributor.JBXDistributor_ZeroJBX.selector);
        d.setJBX({jbx: IJBActiveVotes(address(0))});

        // First nonzero set succeeds and is recorded.
        d.setJBX({jbx: IJBActiveVotes(address(first))});
        assertEq(address(d.JBX()), address(first), "JBX not recorded");

        // Any later set reverts, even to a different token.
        vm.expectRevert(
            abi.encodeWithSelector(JBXDistributor.JBXDistributor_JBXAlreadySet.selector, IJBActiveVotes(address(first)))
        );
        d.setJBX({jbx: IJBActiveVotes(address(second))});

        // The configured JBX is unchanged after the rejected replacement.
        assertEq(address(d.JBX()), address(first), "JBX replaced after lock");
    }

    /// @notice FUZZ: direct `fund` is always disabled regardless of arguments, so rewards can only enter through
    /// split hooks or sucker settlement.
    /// @param hook An arbitrary hook address.
    /// @param token An arbitrary reward token (the call reverts before any token method is touched).
    /// @param amount An arbitrary amount.
    function testFuzz_directFundingAlwaysReverts(address hook, IERC20 token, uint256 amount) public {
        vm.expectRevert(JBXDistributor.JBXDistributor_DirectFundingDisabled.selector);
        _distributor.fund({hook: hook, token: token, amount: amount});
    }
}
