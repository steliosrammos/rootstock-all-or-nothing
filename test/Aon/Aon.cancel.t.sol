// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AonTestBase.sol";

contract AonRefundTest is AonTestBase {
    function test_Cancel_SuccessByCreator() public {
        vm.prank(creator);
        vm.expectEmit(false, false, false, false);
        emit Cancelled();
        aon.cancel();
        assertEq(uint256(aon.status()), uint256(Aon.Status.Cancelled), "Contract should be cancelled");
    }

    function test_Cancel_SuccessByFactoryOwner() public {
        vm.prank(factoryOwner);
        vm.expectEmit(false, false, false, false);
        emit Cancelled();
        aon.cancel();
        assertEq(uint256(aon.status()), uint256(Aon.Status.Cancelled), "Contract should be cancelled");
    }

    function test_Cancel_FailsIfUnauthorized() public {
        vm.prank(randomAddress);
        vm.expectRevert(Aon.OnlyCreatorOrFactoryOwnerCanCancel.selector);
        aon.cancel();
    }

    function test_Cancel_FailsIfAlreadyCancelled() public {
        vm.prank(creator);
        aon.cancel();

        vm.prank(creator);
        vm.expectRevert(Aon.CannotCancelCancelledContract.selector);
        aon.cancel();
    }

    function test_Cancel_FailsIfClaimed() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);
        vm.prank(creator);
        aon.claim(0);

        vm.prank(creator);
        vm.expectRevert(Aon.CannotCancelClaimedContract.selector);
        aon.cancel();
    }

    function test_Cancel_FailsIfFinalized() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        vm.warp(aon.endTime() + 1 days);
        vm.prank(contributor1);
        aon.refund(0);
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        vm.prank(creator);
        vm.expectRevert(Aon.CannotCancelFinalizedContract.selector);
        aon.cancel();
    }
}
