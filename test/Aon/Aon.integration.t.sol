// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AonTestBase.sol";

contract AonIntegrationTest is AonTestBase {
    /*
    * INTEGRATION TESTS
    */

    function test_Contribute_ThenRefund_ThenContributeAgain() public {
        // First contribution
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        assertEq(aon.contributions(contributor1), 1 ether, "First contribution should be recorded");

        // Refund during active campaign (before goal reached, before endTime)
        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund(0);
        assertEq(contributor1.balance, contributorInitialBalance + 1 ether, "Contributor should get money back");
        assertEq(aon.contributions(contributor1), 0, "Contribution should be cleared");

        // Contribute again - should work (campaign is still active)
        vm.prank(contributor1);
        aon.contribute{value: 2 ether}(0, 0);
        assertEq(aon.contributions(contributor1), 2 ether, "Second contribution should be recorded");
    }

    function test_Claim_WithZeroClaimableBalance_OnlyFees() public {
        // Contribute with creator fees equal to contribution
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(GOAL, 0); // All goes to creator fee

        vm.warp(aon.endTime() + 1 days);
        assertEq(aon.claimableBalance(), 0, "Claimable balance should be zero");

        uint256 creatorInitialBalance = creator.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.prank(creator);
        aon.claim(0);

        // Creator should receive nothing, fee recipient should receive all
        assertEq(creator.balance, creatorInitialBalance, "Creator should receive nothing");
        assertEq(feeRecipient.balance, feeRecipientInitialBalance + GOAL, "Fee recipient should receive all funds");
        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(uint256(aon.status()), uint256(Aon.Status.Claimed), "Status should be Claimed");
    }

    function test_SwipeFunds_WithOnlyContributorFees() public {
        uint256 contributorFee = 0.1 ether;
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, contributorFee);

        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        uint256 feeRecipientInitialBalance = feeRecipient.balance;
        uint256 swipeRecipientInitialBalance = swipeRecipient.balance;

        vm.prank(factoryOwner);
        aon.swipeFunds();

        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + contributorFee,
            "Fee recipient should receive contributor fees"
        );
        assertEq(
            swipeRecipient.balance,
            swipeRecipientInitialBalance + (1 ether - contributorFee),
            "Swipe recipient should receive remaining funds"
        );
    }

    function test_CompleteFlow_GoalReached_Claimed() public {
        // Contribute to reach goal
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(0, 0);
        vm.prank(contributor2);
        aon.contribute{value: 5 ether}(0, 0);

        assertEq(aon.goalBalance(), 10 ether, "Goal balance should be 10 ether");
        assertTrue(aon.goalBalance() >= GOAL, "Goal should be reached");

        // Fast-forward past end time
        vm.warp(aon.endTime() + 1 days);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Successful), "Status should be Successful");

        // Creator claims
        uint256 creatorInitialBalance = creator.balance;
        vm.prank(creator);
        aon.claim(0);

        assertEq(creator.balance, creatorInitialBalance + 10 ether, "Creator should receive all funds");
        assertEq(address(aon).balance, 0, "Contract should be empty");
        assertEq(uint256(aon.status()), uint256(Aon.Status.Claimed), "Status should be Claimed");
    }

    function test_CompleteFlow_GoalNotReached_Refunded() public {
        // Contribute but don't reach goal
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(0, 0);

        // Fast-forward past end time
        vm.warp(aon.endTime() + 1 days);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Failed), "Status should be Failed");

        // Contributor refunds
        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund(0);

        assertEq(contributor1.balance, contributorInitialBalance + 5 ether, "Contributor should get money back");
        assertEq(aon.contributions(contributor1), 0, "Contribution should be cleared");
    }

    function test_CompleteFlow_GoalReached_Unclaimed_Swiped() public {
        // Contribute to reach goal
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past claim window (becomes unclaimed)
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Unclaimed), "Status should be Unclaimed");

        // Fast-forward past refund window
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        // Capture values before swiping
        uint256 feeRecipientInitialBalance = feeRecipient.balance;
        uint256 swipeRecipientInitialBalance = swipeRecipient.balance;
        uint256 claimableAmount = aon.claimableBalance();
        uint256 totalFees = aon.totalCreatorFee() + aon.totalContributorFee();

        vm.prank(factoryOwner);
        aon.swipeFunds();

        // For unclaimed contracts, fees go to fee recipient, rest to swipe recipient
        assertEq(
            feeRecipient.balance, feeRecipientInitialBalance + totalFees, "Fee recipient should receive platform fees"
        );
        assertEq(
            swipeRecipient.balance,
            swipeRecipientInitialBalance + claimableAmount,
            "Swipe recipient should receive claimable amount"
        );
        assertEq(address(aon).balance, 0, "Contract should be empty");
    }

    function test_MultipleContributors_MultipleRefunds() public {
        // Multiple contributors
        vm.prank(contributor1);
        aon.contribute{value: 3 ether}(0, 0);
        vm.prank(contributor2);
        aon.contribute{value: 2 ether}(0, 0);

        // Cancel to allow refunds
        vm.prank(creator);
        aon.cancel();

        // Refund contributor1
        uint256 contributor1InitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund(0);
        assertEq(contributor1.balance, contributor1InitialBalance + 3 ether, "Contributor1 should get money back");

        // Refund contributor2
        uint256 contributor2InitialBalance = contributor2.balance;
        vm.prank(contributor2);
        aon.refund(0);
        assertEq(contributor2.balance, contributor2InitialBalance + 2 ether, "Contributor2 should get money back");

        assertEq(address(aon).balance, 0, "Contract should be empty");
    }
}

