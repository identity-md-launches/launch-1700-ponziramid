// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PonziramidToken} from "src/PonziramidToken.sol";

/// @dev All funds stay within five actors. Only this handler is targeted by the invariant runner.
/// Ghost credits/debits record successful instructions, never balances read back from the token.
/// Bounds also come from this independent ledger, so a wrong balance cannot hide an invalid transition.
contract PonziramidHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PonziramidToken public immutable token;
    address[5] public actors;
    mapping(address => uint256) public credited;
    mapping(address => uint256) public debited;
    mapping(address => mapping(address => uint256)) public lastApproval;
    mapping(address => mapping(address => uint256)) public spentSinceApproval;

    constructor(PonziramidToken token_, address[5] memory actors_) {
        token = token_;
        actors = actors_;
        credited[actors_[0]] = SUPPLY;
    }

    function expectedBalance(address actor) public view returns (uint256) {
        return credited[actor] - debited[actor];
    }

    function expectedAllowance(address owner, address spender) public view returns (uint256) {
        uint256 approved = lastApproval[owner][spender];
        return approved == type(uint256).max ? approved : approved - spentSinceApproval[owner][spender];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), bound(amountSeed, 0, expectedBalance(from)));
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), expectedBalance(from));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value, uint8 mode) external {
        // Exercise zero/revocation, infinite, just-below-infinite and ordinary approvals frequently.
        mode %= 5;
        if (mode == 0) value = 0;
        else if (mode == 1) value = type(uint256).max;
        else if (mode == 2) value = type(uint256).max - 1;
        else if (mode == 3) value = bound(value, 0, SUPPLY);
        _approve(_actor(ownerSeed), _actor(spenderSeed), value);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 available = expectedBalance(owner);
        uint256 allowed = expectedAllowance(owner, spender);
        uint256 value = bound(amountSeed, 0, available < allowed ? available : allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, value), "valid delegated transfer returned false");
        credited[to] += value;
        debited[owner] += value;
        // Cumulative spending is a separate ledger, reset only when the holder changes approval.
        spentSinceApproval[owner][spender] += value;
    }

    function rejectAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(ownerSeed % actors.length + 1);
        uint256 held = expectedBalance(owner);
        uint256 value = bound(amountSeed, held + 1, type(uint256).max);
        if (delegated) _approve(owner, spender, value);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientBalance.selector, owner, held, value));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, to, value);
        else token.transfer(to, value);
        // No ledger update: failure must roll back both the allowance and the balances.
    }

    function rejectAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 allowedSeed) external {
        // Find a funded owner without discarding this step, even after full-balance sweeps.
        address owner = _actor(ownerSeed);
        for (uint256 i; i < actors.length; ++i) {
            if (expectedBalance(actors[i]) > expectedBalance(owner)) owner = actors[i];
        }
        address spender = _actor(spenderSeed);
        uint256 held = expectedBalance(owner);
        assertGt(held, 0, "the closed actor set lost all funds");
        uint256 allowed = bound(allowedSeed, 0, held - 1);
        _approve(owner, spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, allowed + 1);
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 value = bound(amountSeed, 0, expectedBalance(owner));
        if (delegated) _approve(owner, spender, value);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), value);
        else token.transfer(address(0), value);
    }

    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, spender, 1);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _approve(address owner, address spender, uint256 value) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, value), "valid approval returned false");
        lastApproval[owner][spender] = value;
        spentSinceApproval[owner][spender] = 0;
    }

    function _transfer(address from, address to, uint256 value) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, value), "valid transfer returned false");
        credited[to] += value;
        debited[from] += value;
    }
}

/// @notice Fixed supply, exact holder accounting, and authorization under mixed successful/failing calls.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PonziramidTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PonziramidToken internal token;
    PonziramidHandler internal handler;
    address[5] internal actors;

    function setUp() public {
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
        }
        vm.prank(actors[0]);
        token = new PonziramidToken();
        handler = new PonziramidHandler(token, actors);

        // Start with funds at every actor and both finite and infinite approvals. All funding is
        // real transfer activity recorded in the ledger, with no storage edits or token balance deals.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, SUPPLY / actors.length);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, SUPPLY / actors.length, i % 2 == 0 ? 1 : 3);
        }

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferFullBalance.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.rejectAboveBalance.selector;
        selectors[5] = handler.rejectAboveAllowance.selector;
        selectors[6] = handler.rejectZeroReceiver.selector;
        selectors[7] = handler.revokeAndReject.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyEqualsSumOfAllReachableBalances() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "fixed supply changed");
        assertEq(sum, SUPPLY, "tokens created, destroyed or diverted outside the actor set");
        assertEq(token.balanceOf(address(0)), 0, "zero address acquired tokens");
        assertEq(token.balanceOf(address(token)), 0, "unrequested transfer to the token");
        assertEq(token.balanceOf(address(handler)), 0, "unrequested transfer to the handler");
    }

    function invariant_eachBalanceMatchesAuthorizedTransfers() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "holder accounting mismatch");
        }
    }

    function invariant_allAllowancesMatchApprovalAndSpendingHistory() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "allowance isolation, overwrite, spending or rollback failed"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
        }
    }

    /// @dev End each random sequence by proving that every holder can still move its whole balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transferFullBalance(i, 0);
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY, "holders could not recover the complete supply");
        invariant_supplyEqualsSumOfAllReachableBalances();
        invariant_eachBalanceMatchesAuthorizedTransfers();
        invariant_allAllowancesMatchApprovalAndSpendingHistory();
    }

    /// @dev Deterministic check that every handler branch is live before trusting the random campaign.
    function test_handlerExercisesValidAndRejectedTransitions() public {
        handler.transfer(0, 1, 1);
        handler.transfer(1, 1, 1);
        handler.approve(1, 2, 2, 4);
        handler.transferFrom(1, 2, 3, 1);
        handler.transferFrom(1, 2, 1, 1);
        assertEq(token.allowance(actors[1], actors[2]), 0);
        handler.approve(1, 2, 0, 1);
        handler.transferFrom(1, 2, 3, 1);
        assertEq(token.allowance(actors[1], actors[2]), type(uint256).max);
        handler.rejectAboveBalance(0, 1, type(uint256).max, false);
        handler.rejectAboveBalance(0, 1, SUPPLY, true);
        handler.rejectAboveAllowance(0, 1, 1);
        handler.rejectZeroReceiver(1, 2, 1, false);
        handler.rejectZeroReceiver(1, 2, 1, true);
        handler.revokeAndReject(1, 2);
        handler.transferFullBalance(1, 0);
        invariant_supplyEqualsSumOfAllReachableBalances();
        invariant_eachBalanceMatchesAuthorizedTransfers();
        invariant_allAllowancesMatchApprovalAndSpendingHistory();
        afterInvariant();
    }
}
