// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBSingleAllowance} from "@bananapus/core-v6/src/structs/JBSingleAllowance.sol";

import {REVLoan} from "../structs/REVLoan.sol";

/// @notice Minimal interface for Revnet loans used by the distributor's vesting-collateral path.
interface IREVLoans {
    /// @notice Open a loan by borrowing from a revnet and burning vesting reward collateral.
    /// @param revnetId The ID of the revnet to borrow from.
    /// @param token The token to borrow from the revnet.
    /// @param minBorrowAmount The minimum amount to borrow, denominated in `token`.
    /// @param collateralCount The amount of collateral tokens to burn.
    /// @param beneficiary The address receiving the borrowed funds.
    /// @param prepaidFeePercent The fee percent to charge upfront.
    /// @param holder The address whose tokens are used as collateral and who receives the loan NFT.
    /// @return loanId The loan ID created.
    /// @return loan The loan data created.
    function borrowFrom(
        uint256 revnetId,
        address token,
        uint256 minBorrowAmount,
        uint256 collateralCount,
        address payable beneficiary,
        uint256 prepaidFeePercent,
        address holder
    )
        external
        returns (uint256 loanId, REVLoan memory loan);

    /// @notice Determine the source fee amount needed to repay a loan amount.
    /// @param loan The loan data.
    /// @param amount The amount to repay.
    /// @return sourceFeeAmount The source fee amount.
    function determineSourceFeeAmount(
        REVLoan memory loan,
        uint256 amount
    )
        external
        view
        returns (uint256 sourceFeeAmount);

    /// @notice Return a loan's stored data.
    /// @param loanId The loan ID to look up.
    /// @return loan The loan data.
    function loanOf(uint256 loanId) external view returns (REVLoan memory loan);

    /// @notice Repay a loan and return collateral to a beneficiary.
    /// @param loanId The loan ID to repay.
    /// @param maxRepayBorrowAmount The maximum amount to repay, denominated in the source token.
    /// @param collateralCountToReturn The amount of collateral to return.
    /// @param beneficiary The address receiving returned collateral.
    /// @param allowance A permit2 allowance used by Revnet loans if needed.
    /// @return paidOffLoanId The paid-off loan ID returned by Revnet loans.
    /// @return paidOffLoan The paid-off loan data.
    function repayLoan(
        uint256 loanId,
        uint256 maxRepayBorrowAmount,
        uint256 collateralCountToReturn,
        address payable beneficiary,
        JBSingleAllowance calldata allowance
    )
        external
        payable
        returns (uint256 paidOffLoanId, REVLoan memory paidOffLoan);
}
