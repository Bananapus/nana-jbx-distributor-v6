// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBToken} from "@bananapus/core-v6/src/interfaces/IJBToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice ERC-20 project-token mock implementing the Juicebox token surface used by tests.
contract MockJBToken is ERC20, IJBToken {
    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @notice Initializes the mock token metadata.
    /// @param name The token name.
    /// @param symbol The token symbol.
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Burn tokens from an account.
    /// @param account The account whose tokens are burned.
    /// @param amount The number of tokens to burn.
    function burn(address account, uint256 amount) external override {
        _burn({account: account, value: amount});
    }

    /// @notice Initialize token metadata.
    /// @param name The token name.
    /// @param symbol The token symbol.
    /// @param tokensAddress The token registry address.
    function initialize(string memory name, string memory symbol, address tokensAddress) external pure override {
        name;
        symbol;
        tokensAddress;
    }

    /// @notice Mint tokens to an account.
    /// @param account The account receiving tokens.
    /// @param amount The number of tokens to mint.
    function mint(address account, uint256 amount) external override {
        _mint({account: account, value: amount});
    }

    /// @notice Set token metadata.
    /// @param name The token name.
    /// @param symbol The token symbol.
    function setMetadata(string memory name, string memory symbol) external pure override {
        name;
        symbol;
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the balance of an account.
    /// @param account The account to get the balance of.
    /// @return balance The account's balance.
    function balanceOf(address account) public view override(ERC20, IJBToken) returns (uint256 balance) {
        balance = super.balanceOf(account);
    }

    /// @notice Whether this token can be added to a project.
    /// @param projectId The project ID to check.
    /// @return canAdd Always true for this mock.
    function canBeAddedTo(uint256 projectId) external pure override returns (bool canAdd) {
        projectId;
        canAdd = true;
    }

    /// @notice Returns the number of decimals used by the token.
    /// @return tokenDecimals The token decimals.
    function decimals() public view override(ERC20, IJBToken) returns (uint8 tokenDecimals) {
        tokenDecimals = super.decimals();
    }

    /// @notice Returns the total token supply.
    /// @return supply The total token supply.
    function totalSupply() public view override(ERC20, IJBToken) returns (uint256 supply) {
        supply = super.totalSupply();
    }
}
