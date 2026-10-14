// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PonziramidToken} from "../src/PonziramidToken.sol";

/// @dev Stands in for the launch factory: creates the token with CREATE2 so the test can check that the
///      supply lands on the creator, whatever address that is, and that no constructor argument is needed.
contract FactoryStub {
    function deploy(bytes32 salt) external returns (PonziramidToken token) {
        token = new PonziramidToken{salt: salt}();
    }
}

contract PonziramidTokenTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    PonziramidToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        vm.prank(deployer);
        token = new PonziramidToken();
    }

    // ------------------------------------------------------------------------------------------------
    // Metadata and supply
    // ------------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "PONZIRAMID");
        assertEq(token.symbol(), "PONZIRAM");
        assertEq(token.decimals(), 18);
    }

    function test_supplyIsOneBillionWith18Decimals() public view {
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        new PonziramidToken();
    }

    /// @dev The launch factory creates the token with CREATE2 and holds the supply afterwards. The
    ///      recipient is whichever contract ran the constructor, never a hard-coded address.
    function test_create2DeploymentMintsToTheCreatingContract() public {
        FactoryStub factory = new FactoryStub();
        PonziramidToken launched = factory.deploy(bytes32(uint256(42)));
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(deployer), 0);
    }

    function test_twoDeploymentsAreIndependent() public {
        vm.prank(alice);
        PonziramidToken second = new PonziramidToken();
        assertEq(second.balanceOf(alice), SUPPLY);
        assertEq(second.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    // ------------------------------------------------------------------------------------------------
    // transfer
    // ------------------------------------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        uint256 amount = 1_234 ether;
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(deployer);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        token.transfer(deployer, 5 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(PonziramidToken.ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(alice);
        token.transfer(bob, 11 ether);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transfer(alice, 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
    }

    // ------------------------------------------------------------------------------------------------
    // approve / allowance / transferFrom
    // ------------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, alice, 7 ether);
        vm.prank(deployer);
        assertTrue(token.approve(alice, 7 ether));
        assertEq(token.allowance(deployer, alice), 7 ether);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(alice, 7 ether);
        token.approve(alice, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 3 ether);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowanceAndMovesTokens() public {
        vm.prank(deployer);
        token.approve(alice, 100 ether);

        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, bob, 60 ether);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 60 ether));

        assertEq(token.balanceOf(bob), 60 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 60 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, alice), 40 ether);
    }

    function test_transferFromRevertsBeyondAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, alice, 100 ether, 101 ether)
        );
        vm.prank(alice);
        token.transferFrom(deployer, bob, 101 ether);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromRevertsWhenOwnerBalanceTooLow() public {
        vm.prank(deployer);
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(PonziramidToken.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether)
        );
        vm.prank(bob);
        token.transferFrom(alice, carol, 6 ether);
        // The failed call did not consume allowance.
        assertEq(token.allowance(alice, bob), 10 ether);
    }

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(deployer);
        token.approve(alice, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transferFrom(deployer, address(0), 1 ether);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
        assertEq(token.balanceOf(bob), 1 ether);
    }

    function test_allowanceIsPerSpender() public {
        vm.prank(deployer);
        token.approve(alice, 1 ether);
        assertEq(token.allowance(deployer, bob), 0);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, bob, 0, 1 ether));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1 ether);
    }

    // ------------------------------------------------------------------------------------------------
    // No privileged surface: nothing mints, pauses, freezes or seizes
    // ------------------------------------------------------------------------------------------------

    function test_noAdminSelectorChangesSupplyOrBalances() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "transferOwnership(address)",
            "owner()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "setBlacklist(address,bool)",
            "setTransfersEnabled(bool)",
            "upgradeTo(address)",
            "initialize(address)"
        ];
        vm.prank(deployer);
        token.transfer(alice, 1 ether);
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, type(uint128).max);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 1 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1 ether));
        assertEq(token.balanceOf(bob), 1 ether);
    }

    function test_deployerHasNoSpecialPowerOverHolders() public {
        vm.prank(deployer);
        token.transfer(alice, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function test_etherIsRefused() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ------------------------------------------------------------------------------------------------
    // Fuzz: conservation and exactness
    // ------------------------------------------------------------------------------------------------

    function testFuzz_transferIsExactAndConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(to) + token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 attempt) public {
        held = bound(held, 0, SUPPLY - 1);
        attempt = bound(attempt, held + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.expectRevert(abi.encodeWithSelector(PonziramidToken.ERC20InsufficientBalance.selector, alice, held, attempt));
        vm.prank(alice);
        token.transfer(bob, attempt);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 0, SUPPLY);
        spent = bound(spent, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        if (spent > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(PonziramidToken.ERC20InsufficientAllowance.selector, alice, allowed, spent)
            );
            vm.prank(alice);
            token.transferFrom(deployer, bob, spent);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.allowance(deployer, alice), allowed);
        } else {
            vm.prank(alice);
            assertTrue(token.transferFrom(deployer, bob, spent));
            assertEq(token.balanceOf(bob), spent);
            assertEq(token.allowance(deployer, alice), allowed - spent);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_chainOfTransfersConservesSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        c = bound(c, 0, b);
        vm.prank(deployer);
        token.transfer(alice, a);
        vm.prank(alice);
        token.transfer(bob, b);
        vm.prank(bob);
        token.transfer(carol, c);
        assertEq(token.balanceOf(deployer), SUPPLY - a);
        assertEq(token.balanceOf(alice), a - b);
        assertEq(token.balanceOf(bob), b - c);
        assertEq(token.balanceOf(carol), c);
        assertEq(
            token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(carol), SUPPLY
        );
    }
}
