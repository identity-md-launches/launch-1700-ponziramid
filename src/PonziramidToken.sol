// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title PONZIRAMID (PONZIRAM)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 tokens (18 decimals) is minted once, in the
///         constructor, to the deployer (`msg.sender`). Nothing can mint afterwards, there is no owner, no pause,
///         no blocklist and no fee: every transfer moves exactly the amount requested.
/// @dev Self-contained on purpose: no external library, no delegatecall, no selfdestruct, no upgradeability.
///      The Solidity identifier `PonziramidToken` is the contract's launch name; `name()` returns the token's.
contract PonziramidToken {
    // ------------------------------------------------------------------------------------------------
    // Errors (names follow ERC-6093 so wallets and indexers decode them)
    // ------------------------------------------------------------------------------------------------

    /// @notice `sender` holds `balance` but tried to move `needed`.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    /// @notice A transfer from the zero address is never valid.
    error ERC20InvalidSender(address sender);
    /// @notice A transfer to the zero address is refused; use a burn address of your own if you mean to burn.
    error ERC20InvalidReceiver(address receiver);
    /// @notice `spender` may spend `allowance` on behalf of the owner but tried to spend `needed`.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    /// @notice An approval from the zero address is never valid.
    error ERC20InvalidApprover(address approver);
    /// @notice An approval to the zero address is refused.
    error ERC20InvalidSpender(address spender);

    // ------------------------------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ------------------------------------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------------------------------------

    /// @notice Token name.
    string public constant name = "PONZIRAMID";
    /// @notice Token symbol.
    string public constant symbol = "PONZIRAM";
    /// @notice Token decimals.
    uint8 public constant decimals = 18;
    /// @notice The whole supply, in minor units: 1,000,000,000 * 10^18. Minted once; never changes.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(decimals);

    // ------------------------------------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------------------------------------

    mapping(address account => uint256) private _balances;
    mapping(address owner => mapping(address spender => uint256)) private _allowances;

    // ------------------------------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------------------------------

    /// @notice Mints the entire supply to the deployer. No arguments: the supply, name, symbol and decimals
    ///         are constants, and the recipient is whoever creates the contract.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    // ------------------------------------------------------------------------------------------------
    // ERC-20 views
    // ------------------------------------------------------------------------------------------------

    /// @notice Always equals `TOTAL_SUPPLY`: there is no mint and no burn path.
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ------------------------------------------------------------------------------------------------
    // ERC-20 actions
    // ------------------------------------------------------------------------------------------------

    /// @notice Moves `value` from the caller to `to`. Reverts rather than returning false on any failure.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Sets the caller's allowance for `spender` to exactly `value`.
    /// @dev Standard ERC-20 approve: a holder who wants to change a non-zero allowance safely sets it to
    ///      zero first, or uses the allowance arithmetic in a wallet that does so.
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /// @notice Moves `value` from `from` to `to` on the caller's allowance. An allowance of
    ///         `type(uint256).max` is treated as unlimited and is not decremented.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    // ------------------------------------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert ERC20InsufficientBalance(from, fromBalance, value);
        unchecked {
            // fromBalance >= value was just checked, and the sum of all balances is TOTAL_SUPPLY,
            // which fits in uint256, so neither line can wrap.
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) private {
        if (owner == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) private {
        uint256 current = _allowances[owner][spender];
        if (current == type(uint256).max) return;
        if (current < value) revert ERC20InsufficientAllowance(spender, current, value);
        unchecked {
            _allowances[owner][spender] = current - value;
        }
        // Allowance changes made by transferFrom are not announced with Approval, matching the
        // common OpenZeppelin behaviour that wallets and indexers already expect.
    }
}
