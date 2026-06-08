// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice ERC-20 that charges a fixed basis-point fee on every transfer. The fee is burned (removed from supply)
/// so `balanceOf(recipient)` only increases by `amount * (BPS_DENOMINATOR - feeBps) / BPS_DENOMINATOR`.
/// @dev Used to exercise `JBDistributor._acceptErc20FundsFrom`'s balance-delta crediting on fee-on-transfer tokens.
contract MockFeeOnTransferToken is ERC20 {
    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice The fee denominator used by `feeBps`.
    uint256 public constant BPS_DENOMINATOR = 10_000;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The fee charged on each transfer, in basis points.
    uint256 public immutable feeBps;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @notice Initializes the mock fee-on-transfer token.
    /// @param initialFeeBps The fee charged on each transfer, in basis points.
    constructor(uint256 initialFeeBps) ERC20("MockFOT", "MFOT") {
        require(initialFeeBps < BPS_DENOMINATOR, "fee >= 100%");
        feeBps = initialFeeBps;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Mint tokens to an account.
    /// @param to The account receiving tokens.
    /// @param amount The number of tokens to mint.
    function mint(address to, uint256 amount) external {
        _mint({account: to, value: amount});
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Apply transfer fees during ERC-20 balance updates.
    /// @param from The account sending tokens.
    /// @param to The account receiving tokens.
    /// @param value The transfer amount before fees.
    function _update(address from, address to, uint256 value) internal override {
        // Mint, burn, and zero-fee transfers keep the base ERC-20 behavior.
        if (from == address(0) || to == address(0) || feeBps == 0) {
            super._update({from: from, to: to, value: value});
            return;
        }

        // Burn the fee so the recipient balance delta is lower than the requested transfer amount.
        uint256 fee = (value * feeBps) / BPS_DENOMINATOR;
        super._update({from: from, to: to, value: value - fee});
        super._update({from: from, to: address(0xdead), value: fee});
    }
}
