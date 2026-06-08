// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";

import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";

import {JBXDistributor} from "../src/JBXDistributor.sol";
import {IREVLoans} from "../src/interfaces/IREVLoans.sol";
import {IREVOwner} from "../src/interfaces/IREVOwner.sol";

/// @notice Deploys the JBX distributor.
contract Deploy is Script {
    /// @notice Deploy the distributor using environment-provided addresses and timing parameters.
    function run() public {
        vm.startBroadcast();

        IJBController controller = IJBController(vm.envAddress("CONTROLLER_ADDRESS"));
        IJBDirectory directory = IJBDirectory(vm.envAddress("DIRECTORY_ADDRESS"));
        IREVLoans revLoans = IREVLoans(vm.envOr("REV_LOANS_ADDRESS", address(0)));
        IREVOwner revOwner = IREVOwner(vm.envOr("REV_OWNER_ADDRESS", address(0)));
        IJBSuckerRegistry suckerRegistry = IJBSuckerRegistry(vm.envAddress("SUCKER_REGISTRY_ADDRESS"));
        IJBTokens tokens = IJBTokens(vm.envAddress("TOKENS_ADDRESS"));

        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 mainnetChainId = vm.envOr("MAINNET_CHAIN_ID", uint256(1));
        uint256 roundDuration = vm.envUint("ROUND_DURATION");
        uint256 vestingRounds = vm.envUint("VESTING_ROUNDS");
        uint256 rawClaimDuration = vm.envUint("CLAIM_DURATION");

        require(rawClaimDuration <= type(uint48).max, "CLAIM_DURATION_TOO_LARGE");

        // Safe because the explicit bound above rejects values larger than uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 claimDuration = uint48(rawClaimDuration);

        new JBXDistributor({
            directory: directory,
            controller: controller,
            tokens: tokens,
            suckerRegistry: suckerRegistry,
            revLoans: revLoans,
            revOwner: revOwner,
            owner: owner,
            mainnetChainId: mainnetChainId,
            initialRoundDuration: roundDuration,
            initialVestingRounds: vestingRounds,
            initialClaimDuration: claimDuration
        });

        vm.stopBroadcast();
    }
}
