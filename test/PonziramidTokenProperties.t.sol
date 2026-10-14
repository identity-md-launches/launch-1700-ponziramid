// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PonziramidToken} from "src/PonziramidToken.sol";

/// @notice Boundary, rollback and algebraic properties supplementing the original launch tests.
/// forge-config: default.fuzz.runs = 1000
contract PonziramidTokenPropertiesTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PonziramidToken internal token;
    address internal holder = makeAddr("properties holder");
    address internal spender = makeAddr("properties spender");
    address internal recipient = makeAddr("properties recipient");
    address internal outsider = makeAddr("properties outsider");

    function setUp() public {
        vm.prank(holder);
        token = new PonziramidToken();
    }

    function test_oneWeiCanBeTransferredAndReturned() public {
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, 1));
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroTransfersEmitAndNeedNoBalanceOrAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(outsider, recipient, 0);
        vm.prank(outsider);
        assertTrue(token.transfer(recipient, 0));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(outsider, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(outsider, recipient, 0));
        assertEq(token.allowance(outsider, spender), 0);
        assertEq(token.balanceOf(outsider), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroApprovalEmitsAndIsIdempotent() public {
        _approve(holder, spender, 1);
        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit Approval(holder, spender, 0);
            _approve(holder, spender, 0);
            assertEq(token.allowance(holder, spender), 0);
        }
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroSenderCannotTransferEvenZero() public {
        // These two zero-caller cases exercise defensive guards, not a claim that an EOA can be zero.
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(recipient, 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroApproverCannotApproveEvenZero() public {
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 0);
        assertEq(token.allowance(address(0), spender), 0);
    }

    function test_transferFromZeroOwnerRejectsZeroValue() public {
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), recipient, 0);
        assertEq(token.allowance(address(0), spender), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroReceiverAndSpenderRejectZeroValue() public {
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(holder);
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, address(0)), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_maximumTransferRevertsWithoutWrappingBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(PonziramidToken.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(holder);
        token.transfer(recipient, type(uint256).max);
        _assertBalances(SUPPLY, 0);
    }

    function test_maximumAllowanceDoesNotPermitSpendingAboveSupply() public {
        _approve(holder, spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(PonziramidToken.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, type(uint256).max);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        _assertBalances(SUPPLY, 0);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        _approve(holder, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), type(uint256).max - 2);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_fullSupplySelfTransferAndDelegatedSelfTransfer() public {
        vm.prank(holder);
        assertTrue(token.transfer(holder, SUPPLY));
        _assertBalances(SUPPLY, 0);

        _approve(holder, spender, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, holder, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, SUPPLY));
        assertEq(token.allowance(holder, spender), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_selfTransferCannotBypassBalanceCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(PonziramidToken.ERC20InsufficientBalance.selector, holder, SUPPLY, SUPPLY + 1)
        );
        vm.prank(holder);
        token.transfer(holder, SUPPLY + 1);
        _assertBalances(SUPPLY, 0);
    }

    function test_ownerCallingTransferFromStillNeedsSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);
        _assertBalances(SUPPLY, 0);

        _approve(holder, holder, 1);
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, holder), 0);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_exhaustedAllowanceCannotBeSpentTwice() public {
        _approve(holder, spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY));
        assertEq(token.allowance(holder, spender), 0);
        _assertBalances(0, SUPPLY);
        // Refill the owner: a second spend must fail because approval was consumed, not lack of funds.
        vm.prank(recipient);
        assertTrue(token.transfer(holder, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        _assertBalances(SUPPLY, 0);
    }

    function test_finiteAndInfiniteApprovalsCanBeRevoked() public {
        uint256[2] memory approvals = [uint256(2), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            _approve(holder, spender, approvals[i]);
            vm.prank(spender);
            assertTrue(token.transferFrom(holder, recipient, 1));
            _approve(holder, spender, 0);
            vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
            vm.prank(spender);
            token.transferFrom(holder, recipient, 1);
            assertEq(token.allowance(holder, spender), 0);
            _assertBalances(SUPPLY - i - 1, i + 1);
        }
    }

    function test_infiniteApprovalCanBeReplacedWithFiniteApproval() public {
        _approve(holder, spender, type(uint256).max);
        _approve(holder, spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_approvalWithoutBalanceWorksAfterFunding() public {
        _approve(outsider, spender, 1);
        vm.prank(holder);
        assertTrue(token.transfer(outsider, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(outsider, recipient, 1));
        assertEq(token.allowance(outsider, spender), 0);
        assertEq(token.balanceOf(outsider), 0);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_allowancesAreIsolatedByBothOwnerAndSpender() public {
        _approve(holder, spender, 7);
        _approve(holder, outsider, 11);
        _approve(outsider, spender, 13);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 3));
        assertEq(token.allowance(holder, spender), 4);
        assertEq(token.allowance(holder, outsider), 11);
        assertEq(token.allowance(outsider, spender), 13);
        assertEq(token.allowance(spender, holder), 0);
        _assertBalances(SUPPLY - 3, 3);
    }

    function testFuzz_zeroReceiverFailureRestoresAllowance(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = bound(allowed, amount, type(uint256).max);
        _approve(holder, spender, allowed);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), amount);
        assertEq(token.allowance(holder, spender), allowed);
        _assertBalances(SUPPLY, 0);
        // The valid retry uses the entire authorization that survived the failed transaction.
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.allowance(holder, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        _assertBalances(SUPPLY - amount, amount);
    }

    function testFuzz_balanceFailureRestoresFiniteAllowance(uint256 held, uint256 attempt) public {
        held = bound(held, 0, SUPPLY - 1);
        attempt = bound(attempt, held + 1, type(uint256).max - 1);
        vm.prank(holder);
        assertTrue(token.transfer(outsider, held));
        _approve(outsider, spender, attempt);
        vm.expectRevert(
            abi.encodeWithSelector(PonziramidToken.ERC20InsufficientBalance.selector, outsider, held, attempt)
        );
        vm.prank(spender);
        token.transferFrom(outsider, recipient, attempt);
        assertEq(token.allowance(outsider, spender), attempt);
        assertEq(token.balanceOf(outsider), held);
        _assertBalances(SUPPLY - held, 0);
    }

    function testFuzz_approvalReplacementAndDirectTransfersAreIndependent(uint256 first, uint256 second, uint256 amount)
        public
    {
        amount = bound(amount, 0, SUPPLY);
        _approve(holder, spender, first);
        _approve(holder, spender, second);
        assertEq(token.allowance(holder, spender), second);
        _assertBalances(SUPPLY, 0);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.allowance(holder, spender), second);
        _assertBalances(SUPPLY - amount, amount);
    }

    function testFuzz_transferRoundTripRestoresBalances(uint256 amount, uint256 cycles) public {
        amount = bound(amount, 0, SUPPLY);
        cycles = bound(cycles, 1, 8);
        for (uint256 i; i < cycles; ++i) {
            vm.prank(holder);
            assertTrue(token.transfer(recipient, amount));
            _assertBalances(SUPPLY - amount, amount);
            vm.prank(recipient);
            assertTrue(token.transfer(holder, amount));
            _assertBalances(SUPPLY, 0);
        }
    }

    function testFuzz_splitDelegatedSpendsEqualOneSpend(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        vm.prank(holder);
        PonziramidToken single = new PonziramidToken();
        _approve(holder, spender, total);
        vm.prank(holder);
        assertTrue(single.approve(spender, total));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, first));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, total - first));
        vm.prank(spender);
        assertTrue(single.transferFrom(holder, recipient, total));
        _assertBalances(SUPPLY - total, total);
        assertEq(token.balanceOf(holder), single.balanceOf(holder));
        assertEq(token.balanceOf(recipient), single.balanceOf(recipient));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(single.allowance(holder, spender), 0);
    }

    function testFuzz_delegatedSelfTransferOnlyConsumesAllowance(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = bound(allowed, amount, type(uint256).max);
        _approve(holder, spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, amount));
        assertEq(token.allowance(holder, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        _assertBalances(SUPPLY, 0);
    }

    function _approve(address owner, address approvedSpender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(approvedSpender, amount));
    }

    function _assertBalances(uint256 holderBalance, uint256 recipientBalance) internal view {
        assertEq(token.balanceOf(holder), holderBalance);
        assertEq(token.balanceOf(recipient), recipientBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
