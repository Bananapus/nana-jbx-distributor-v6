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
import {MockJBToken} from "./mock/MockJBToken.sol";
import {MockJBX} from "./mock/MockJBX.sol";
import {MockSucker} from "./mock/MockSucker.sol";
import {MockSuckerRegistry} from "./mock/MockSuckerRegistry.sol";
import {MockTokens} from "./mock/MockTokens.sol";

/// @notice Unit tests for the JBX-only distributor and its split/sucker reward paths.
contract JBXDistributorTest is Test {
    /// @notice A JBX staker used in claim tests.
    address internal constant _ALICE = address(0xA11CE);

    /// @notice Another JBX staker used as an inactive holder.
    address internal constant _BOB = address(0xB0B);

    /// @notice A delegate address that shows rewards stay with the holder.
    address internal constant _DELEGATE = address(0xD3136A7E);

    /// @notice A helper address that calls permissionless vesting and collection paths.
    address internal constant _HELPER = address(0xE1E1);

    /// @notice The configured mainnet chain ID.
    uint256 internal constant _MAINNET_CHAIN_ID = 1;

    /// @notice A project ID used in split and bridge tests.
    uint256 internal constant _PROJECT_ID = 7;

    /// @notice The round duration used by the test distributor.
    uint256 internal constant _ROUND_DURATION = 1 days;

    /// @notice The remote chain ID used in bridge tests.
    uint256 internal constant _REMOTE_CHAIN_ID = 8453;

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

    /// @notice Deploy a fresh mainnet distributor fixture.
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
            initialClaimDuration: 2 days
        });

        _distributor.setJBX({jbx: IJBActiveVotes(address(_jbx))});
    }

    /// @notice The owner can set JBX once, and the configured JBX token cannot be replaced.
    function test_setJBX_revertsIfAlreadySet() external {
        MockJBX replacementJbx = new MockJBX();

        vm.expectRevert(abi.encodeWithSelector(JBXDistributor.JBXDistributor_JBXAlreadySet.selector, _jbx));
        _distributor.setJBX({jbx: IJBActiveVotes(address(replacementJbx))});
    }

    /// @notice Direct funding is disabled so rewards must arrive through split hooks or sucker settlement.
    function test_fund_reverts() external {
        vm.expectRevert(JBXDistributor.JBXDistributor_DirectFundingDisabled.selector);
        _distributor.fund({hook: address(_jbx), token: IERC20(address(_rewardToken)), amount: 1});
    }

    /// @notice Mainnet split deposits are recorded for the JBX active-voter snapshot denominator.
    function test_processSplitWith_acceptsMainnetSplitRewards() external {
        uint256 amount = 1000 ether;
        uint256 snapshotBlock = block.number - 1;

        _jbx.setPastVotes({account: _ALICE, blockNumber: snapshotBlock, votes: 600 ether});
        _jbx.setPastVotes({account: _BOB, blockNumber: snapshotBlock, votes: 0});
        _jbx.setPastTotalActiveVotes({blockNumber: snapshotBlock, activeVotes: 1000 ether});
        _rewardToken.mint({account: address(this), amount: amount});
        _rewardToken.approve({spender: address(_distributor), value: amount});

        _distributor.processSplitWith(_context({token: address(_rewardToken), amount: amount}));

        (uint208 roundAmount, uint48 recordedSnapshotBlock,, uint48 claimDeadline, uint208 totalStake) = _distributor.rewardRoundOf({
            hook: address(_jbx), groupId: 0, token: IERC20(address(_rewardToken)), round: 0
        });

        assertEq(roundAmount, amount);
        assertEq(recordedSnapshotBlock, snapshotBlock);
        assertEq(claimDeadline, block.timestamp + _ROUND_DURATION + 2 days);
        assertEq(totalStake, 1000 ether);
        assertEq(_distributor.balanceOf({hook: address(_jbx), token: IERC20(address(_rewardToken))}), amount);
    }

    /// @notice Permissionless vesting and collection keep rewards assigned to the encoded holder, not its delegate.
    function test_collectVestedRewards_sendsRewardsToHolderNotDelegate() external {
        uint256 amount = 1000 ether;
        uint256 snapshotBlock = block.number - 1;
        uint256[] memory tokenIds = _singleTokenId(_ALICE);
        IERC20[] memory tokens = _singleToken(address(_rewardToken));

        vm.prank(_ALICE);
        _jbx.delegate(_DELEGATE);

        _jbx.setPastVotes({account: _ALICE, blockNumber: snapshotBlock, votes: 600 ether});
        _jbx.setPastVotes({account: _DELEGATE, blockNumber: snapshotBlock, votes: 0});
        _jbx.setPastTotalActiveVotes({blockNumber: snapshotBlock, activeVotes: 1000 ether});
        _rewardToken.mint({account: address(this), amount: amount});
        _rewardToken.approve({spender: address(_distributor), value: amount});
        _distributor.processSplitWith(_context({token: address(_rewardToken), amount: amount}));

        vm.warp(_distributor.STARTING_TIMESTAMP() + _ROUND_DURATION);
        vm.prank(_HELPER);
        _distributor.beginVesting({tokenIds: tokenIds, tokens: tokens});

        (, uint256 vestingAmount,) =
            _distributor.vestingDataOf(address(_jbx), 0, tokenIds[0], IERC20(address(_rewardToken)), 0);
        assertEq(vestingAmount, 600 ether);

        vm.warp(_distributor.STARTING_TIMESTAMP() + _ROUND_DURATION * 2);
        vm.prank(_HELPER);
        _distributor.collectVestedRewards({
            hook: address(_jbx), tokenIds: tokenIds, tokens: tokens, beneficiary: _ALICE
        });

        assertEq(_rewardToken.balanceOf(_ALICE), 600 ether);
        assertEq(_rewardToken.balanceOf(_DELEGATE), 0);
    }

    /// @notice Remote split deposits must use the project's project token and are queued for a sucker bridge.
    function test_processSplitWith_queuesRemoteProjectTokensForBridge() external {
        vm.chainId(_REMOTE_CHAIN_ID);

        uint256 amount = 1000 ether;
        _projectToken.mint({account: address(this), amount: amount});
        _projectToken.approve({spender: address(_distributor), value: amount});

        _distributor.processSplitWith(_context({token: address(_projectToken), amount: amount}));

        assertEq(
            _distributor.pendingBridgeAmountOf({projectId: _PROJECT_ID, token: IERC20(address(_projectToken))}), amount
        );
        assertEq(_projectToken.balanceOf(address(_distributor)), amount);
    }

    /// @notice Remote split deposits reject non-project tokens because suckers bridge project tokens.
    function test_processSplitWith_revertsOnRemoteNonProjectToken() external {
        vm.chainId(_REMOTE_CHAIN_ID);

        uint256 amount = 1000 ether;
        _rewardToken.mint({account: address(this), amount: amount});
        _rewardToken.approve({spender: address(_distributor), value: amount});

        vm.expectRevert(
            abi.encodeWithSelector(
                JBXDistributor.JBXDistributor_SplitTokenNotBridgeable.selector,
                _PROJECT_ID,
                address(_rewardToken),
                address(_projectToken)
            )
        );
        _distributor.processSplitWith(_context({token: address(_rewardToken), amount: amount}));
    }

    /// @notice Remote bridge keepers prepare queued project tokens through a registered mainnet sucker.
    function test_bridgeToMainnet_preparesSuckerLeaf() external {
        vm.chainId(_REMOTE_CHAIN_ID);

        uint256 amount = 1000 ether;
        MockSucker sucker = new MockSucker({
            initialProjectId: _PROJECT_ID,
            initialPeerChainId: _MAINNET_CHAIN_ID,
            initialProjectToken: IERC20(address(_projectToken)),
            initialRewardToken: _projectToken
        });
        _suckerRegistry.setIsSuckerOf({projectId: _PROJECT_ID, addr: address(sucker), isSucker: true});
        _projectToken.mint({account: address(this), amount: amount});
        _projectToken.approve({spender: address(_distributor), value: amount});
        _distributor.processSplitWith(_context({token: address(_projectToken), amount: amount}));

        uint256 bridged = _distributor.bridgeToMainnet({
            projectId: _PROJECT_ID,
            sucker: IJBSucker(address(sucker)),
            terminalToken: address(_rewardToken),
            amount: 400 ether,
            minTokensReclaimed: 300 ether
        });

        bytes32 expectedBeneficiary = bytes32(uint256(uint160(address(_distributor))));
        bytes32 expectedMetadata =
            _distributor.packLeafMetadata({originChainId: _REMOTE_CHAIN_ID, projectId: _PROJECT_ID});

        assertEq(bridged, 400 ether);
        assertEq(
            _distributor.pendingBridgeAmountOf({projectId: _PROJECT_ID, token: IERC20(address(_projectToken))}),
            600 ether
        );
        assertEq(sucker.lastBeneficiary(), expectedBeneficiary);
        assertEq(sucker.lastMetadata(), expectedMetadata);
        assertEq(sucker.lastProjectTokenCount(), 400 ether);
        assertEq(sucker.lastTerminalToken(), address(_rewardToken));
        assertEq(sucker.lastMinTokensReclaimed(), 300 ether);
        assertEq(_projectToken.balanceOf(address(sucker)), 400 ether);
    }

    /// @notice Mainnet settlement claims a proven sucker leaf and records its project tokens as JBX rewards.
    function test_claimRemoteRewards_settlesSuckerClaimIntoJBXRewards() external {
        vm.chainId(_MAINNET_CHAIN_ID);
        vm.roll(300);

        uint256 snapshotBlock = block.number - 1;
        _jbx.setPastTotalActiveVotes({blockNumber: snapshotBlock, activeVotes: 1000 ether});

        MockSucker sucker = new MockSucker({
            initialProjectId: _PROJECT_ID,
            initialPeerChainId: _REMOTE_CHAIN_ID,
            initialProjectToken: IERC20(address(_projectToken)),
            initialRewardToken: _projectToken
        });
        _suckerRegistry.setIsSuckerOf({projectId: _PROJECT_ID, addr: address(sucker), isSucker: true});

        JBClaim memory claimData = _claim({
            terminalToken: address(_rewardToken),
            index: 1,
            projectTokenCount: 250 ether,
            terminalTokenAmount: 125 ether,
            metadata: _distributor.packLeafMetadata({originChainId: _REMOTE_CHAIN_ID, projectId: _PROJECT_ID})
        });

        uint256 rewardAmount = _distributor.claimRemoteRewards({
            originChainId: _REMOTE_CHAIN_ID,
            projectId: _PROJECT_ID,
            sucker: IJBSucker(address(sucker)),
            claimData: claimData
        });

        (uint208 roundAmount, uint48 recordedSnapshotBlock,, uint48 claimDeadline, uint208 totalStake) = _distributor.rewardRoundOf({
            hook: address(_jbx), groupId: 0, token: IERC20(address(_projectToken)), round: 0
        });

        assertEq(rewardAmount, 250 ether);
        assertTrue(
            _distributor.settledLeafOf({
                sucker: IJBSucker(address(sucker)), terminalToken: address(_rewardToken), leafIndex: 1
            })
        );
        assertEq(roundAmount, 250 ether);
        assertEq(recordedSnapshotBlock, snapshotBlock);
        assertEq(claimDeadline, block.timestamp + _ROUND_DURATION + 2 days);
        assertEq(totalStake, 1000 ether);
        assertEq(_projectToken.balanceOf(address(_distributor)), 250 ether);
    }

    /// @notice A settled sucker leaf cannot be recorded into rewards twice.
    function test_claimRemoteRewards_revertsIfLeafAlreadySettled() external {
        vm.chainId(_MAINNET_CHAIN_ID);
        vm.roll(300);

        uint256 snapshotBlock = block.number - 1;
        _jbx.setPastTotalActiveVotes({blockNumber: snapshotBlock, activeVotes: 1000 ether});

        MockSucker sucker = new MockSucker({
            initialProjectId: _PROJECT_ID,
            initialPeerChainId: _REMOTE_CHAIN_ID,
            initialProjectToken: IERC20(address(_projectToken)),
            initialRewardToken: _projectToken
        });
        _suckerRegistry.setIsSuckerOf({projectId: _PROJECT_ID, addr: address(sucker), isSucker: true});

        JBClaim memory claimData = _claim({
            terminalToken: address(_rewardToken),
            index: 1,
            projectTokenCount: 250 ether,
            terminalTokenAmount: 125 ether,
            metadata: _distributor.packLeafMetadata({originChainId: _REMOTE_CHAIN_ID, projectId: _PROJECT_ID})
        });
        _distributor.claimRemoteRewards({
            originChainId: _REMOTE_CHAIN_ID,
            projectId: _PROJECT_ID,
            sucker: IJBSucker(address(sucker)),
            claimData: claimData
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                JBXDistributor.JBXDistributor_LeafAlreadySettled.selector, address(sucker), address(_rewardToken), 1
            )
        );
        _distributor.claimRemoteRewards({
            originChainId: _REMOTE_CHAIN_ID,
            projectId: _PROJECT_ID,
            sucker: IJBSucker(address(sucker)),
            claimData: claimData
        });
    }

    /// @notice Build a sucker claim for the distributor as beneficiary.
    /// @param terminalToken The terminal token in the sucker leaf.
    /// @param index The sucker leaf index.
    /// @param projectTokenCount The number of project tokens in the leaf.
    /// @param terminalTokenAmount The number of terminal tokens in the leaf.
    /// @param metadata The leaf metadata.
    /// @return claimData The claim data.
    function _claim(
        address terminalToken,
        uint256 index,
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 metadata
    )
        internal
        view
        returns (JBClaim memory claimData)
    {
        bytes32[32] memory proof;

        claimData = JBClaim({
            token: terminalToken,
            leaf: JBLeaf({
                index: index,
                beneficiary: bytes32(uint256(uint160(address(_distributor)))),
                projectTokenCount: projectTokenCount,
                terminalTokenAmount: terminalTokenAmount,
                metadata: metadata
            }),
            proof: proof
        });
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

    /// @notice Build a single reward-token array.
    /// @param token The reward token address.
    /// @return tokens The single-item reward-token array.
    function _singleToken(address token) internal pure returns (IERC20[] memory tokens) {
        tokens = new IERC20[](1);
        tokens[0] = IERC20(token);
    }

    /// @notice Build a single encoded-staker-address array.
    /// @param account The account to encode.
    /// @return tokenIds The single-item encoded staker address array.
    function _singleTokenId(address account) internal pure returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](1);
        tokenIds[0] = uint256(uint160(account));
    }
}
