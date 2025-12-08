// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AonTestBase.sol";

contract AonGetStatusTest is AonTestBase {
    /*
    * GET STATUS TESTS
    */

    function test_GetStatus_ReturnsActive_WhenCampaignIsRunning() public {
        // No contributions yet, before end time
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Active), "Should be Active initially");

        // Some contributions but goal not reached, before end time
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Active), "Should be Active when goal not reached");
    }

    function test_GetStatus_ReturnsSuccessful_WhenGoalReachedWithinClaimWindow() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past end time but still within claim window
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.endTime() + aon.claimWindow() > block.timestamp, "Should still be within claim window");

        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Successful), "Should be Successful");
    }

    function test_GetStatus_ReturnsUnclaimed_WhenGoalReachedButClaimWindowPassed() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past claim window
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Unclaimed), "Should be Unclaimed");
    }

    function test_GetStatus_ReturnsUnclaimed_WhenStatusIsSetToUnclaimed() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past claim window
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);

        // First refund sets status to Unclaimed
        vm.prank(contributor1);
        aon.refund(0);

        // Verify status is stored as Unclaimed
        assertEq(uint256(aon.status()), uint256(Aon.Status.Unclaimed), "Stored status should be Unclaimed");
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Unclaimed), "getStatus should return Unclaimed");
    }

    function test_GetStatus_ReturnsUnclaimed_AfterBalanceDropsBelowGoal() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.prank(contributor2);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past claim window
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);

        // First refund drops balance below goal
        vm.prank(contributor1);
        aon.refund(0);

        // Status should still be Unclaimed even though balance is below goal
        assertTrue(aon.goalBalance() < GOAL, "Balance should be below goal");
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Unclaimed), "Should remain Unclaimed");
    }

    function test_GetStatus_ReturnsFailed_WhenGoalNotReachedAndTimeExpired() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL - 1 ether}(0, 0); // Goal not reached

        // Fast-forward past end time
        vm.warp(aon.endTime() + 1 days);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Failed), "Should be Failed");
    }

    function test_GetStatus_ReturnsCancelled_WhenContractIsCancelled() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        vm.prank(creator);
        aon.cancel();

        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Cancelled), "Should be Cancelled");
    }

    function test_GetStatus_ReturnsClaimed_WhenFundsAreClaimed() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        vm.warp(aon.endTime() + 1 days);

        vm.prank(creator);
        aon.claim(0);

        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Claimed), "Should be Claimed");
    }

    function test_GetStatus_ReturnsFinalized_WhenContractIsEmptyAndWindowsExpired() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past all windows
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        // Swipe funds to empty the contract
        vm.prank(factoryOwner);
        aon.swipeFunds(feeRecipient);

        assertEq(address(aon).balance, 0, "Contract should be empty");
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Finalized), "Should be Finalized");
    }

    function test_GetStatus_ReturnsFinalized_AfterAllRefundsAndWindowsExpired() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past end time
        vm.warp(aon.endTime() + 1 days);

        // Refund all contributions
        vm.prank(contributor1);
        aon.refund(0);

        // Fast-forward past all windows
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        assertEq(address(aon).balance, 0, "Contract should be empty");
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Finalized), "Should be Finalized");
    }

    function test_GetStatus_CancelledTakesPriorityOverDerivedStates() public {
        // Test that Cancelled takes priority over derived states like Successful
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days); // Would be Successful
        vm.prank(creator);
        aon.cancel();
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Cancelled), "Cancelled should override Successful");
    }

    function test_GetStatus_ClaimedTakesPriorityOverDerivedStates() public {
        // Test that Claimed takes priority over derived states like Successful
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);
        vm.prank(creator);
        aon.claim(0);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Claimed), "Claimed should override Successful");
    }

    function test_GetStatus_StoredUnclaimedTakesPriority() public {
        // Test that stored Unclaimed status is returned correctly
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);
        vm.prank(contributor1);
        aon.refund(0); // Sets status to Unclaimed
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Unclaimed), "Stored Unclaimed should be returned");
    }
}

