// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {mulDiv} from "@prb/math/src/Common.sol";

/// @notice Halmos smoke proofs for `JBXDistributor`'s tractable arithmetic: the leaf-metadata bit-packing and the
/// pro-rata floor-share split.
/// @dev The bit-packing layout is reproduced here as a free function so the proofs stay pure (no deployed
/// contract) and resolve quickly. The `mulDiv` pro-rata cases use concrete boundary tables to keep the 512-bit
/// path out of the symbolic solver; the full-domain `mulDiv` lives in the forge fuzz twins in
/// `JBXDistributorProperties`.
contract JBXDistributorHalmos {
    /// @notice Pack bridge attribution the same way `JBXDistributor.packLeafMetadata` does.
    /// @param originChainId The origin chain ID (must fit uint32).
    /// @param projectId The project ID (must fit uint64).
    /// @return metadata The packed metadata.
    function _pack(uint256 originChainId, uint256 projectId) internal pure returns (uint256 metadata) {
        // Layout: bits [95:64] = originChainId, bits [63:0] = projectId.
        metadata = (originChainId << 64) | projectId;
    }

    /// @notice Proves packing then masking recovers each field with no cross-field bleed.
    /// @param originChainId An in-range origin chain ID (fits uint32).
    /// @param projectId An in-range project ID (fits uint64).
    function check_packLeafMetadataRoundtrip(uint32 originChainId, uint64 projectId) public pure {
        uint256 packed = _pack({originChainId: uint256(originChainId), projectId: uint256(projectId)});

        assert(packed & type(uint64).max == uint256(projectId));
        assert((packed >> 64) & type(uint32).max == uint256(originChainId));
        assert(packed >> 96 == 0);
    }

    /// @notice Proves two distinct in-range pairs never collide on the same packed metadata.
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
        pure
    {
        if (originA == originB && projectA == projectB) return;

        uint256 a = _pack({originChainId: uint256(originA), projectId: uint256(projectA)});
        uint256 b = _pack({originChainId: uint256(originB), projectId: uint256(projectB)});

        assert(a != b);
    }

    /// @notice Proves a round's floor shares never over-distribute the pot at representative split boundaries.
    /// @dev Concrete boundary table keeps the 512-bit `mulDiv` out of the symbolic solver.
    function check_proRataBoundaryTable() public pure {
        // Even split: two equal stakers each take floor(half) and never exceed the pot.
        uint256 even = mulDiv({x: 1000, y: 500, denominator: 1000});
        assert(even + even <= 1000);

        // Lopsided split with floor dust: 1/3 + 2/3 of a pot that does not divide evenly.
        uint256 third = mulDiv({x: 100, y: 1, denominator: 3});
        uint256 twoThirds = mulDiv({x: 100, y: 2, denominator: 3});
        assert(third + twoThirds <= 100);

        // A sole staker holding the entire denominator receives the whole pot.
        assert(mulDiv({x: 100, y: 7, denominator: 7}) == 100);
    }
}
