// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AonTestBase.sol";

contract AonContributeTest is AonTestBase {
    /*
    * CONTRIBUTE TESTS
    */

    function test_Contribute_Success() public {
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit ContributionReceived(contributor1, CONTRIBUTION_AMOUNT);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        assertEq(address(aon).balance, CONTRIBUTION_AMOUNT, "Contract balance should increase");
        assertEq(aon.contributions(contributor1), CONTRIBUTION_AMOUNT, "Contributor's balance should be recorded");
    }

    function test_Contribute_FailsIfZeroAmount() public {
        vm.prank(contributor1);
        vm.expectRevert(Aon.InvalidContribution.selector);
        aon.contribute{value: 0}(0, 0);
    }

    function test_Contribute_FailsIfAfterEndTime() public {
        vm.warp(aon.endTime() + 1 days);
        vm.prank(contributor1);
        vm.expectRevert(Aon.CannotContributeAfterEndTime.selector);
        aon.contribute{value: 1 ether}(0, 0);
    }

    function test_Contribute_FailsIfCancelled() public {
        vm.prank(creator);
        aon.cancel();

        vm.prank(contributor1);
        vm.expectRevert(Aon.CannotContributeToCancelledContract.selector);
        aon.contribute{value: 1 ether}(0, 0);
    }

    /*
    * CONTRIBUTOR FEE TESTS
    */

    function test_Contribute_WithContributorFee_Success() public {
        uint256 contributorFeeAmount = PROCESSING_FEE;
        uint256 expectedContribution = CONTRIBUTION_AMOUNT - contributorFeeAmount;

        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit ContributionReceived(contributor1, expectedContribution);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, contributorFeeAmount);

        assertEq(address(aon).balance, CONTRIBUTION_AMOUNT, "Contract balance should include contributor fee");
        assertEq(aon.contributions(contributor1), expectedContribution, "Contribution should exclude contributor fee");
        assertEq(aon.totalContributorFee(), contributorFeeAmount, "Total contributor fee should be tracked");
    }

    function test_Contribute_WithContributorFee_FailsIfContributorFeeExceedsContribution() public {
        uint256 contributorFeeAmount = 1.1 ether; // Contributor fee exceeds contribution

        vm.prank(contributor1);
        vm.expectRevert(Aon.ContributorFeeCannotExceedContributionAmount.selector);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, contributorFeeAmount);
    }

    function test_Contribute_WithContributorFee_FailsIfContributorFeeEqualsContribution() public {
        uint256 contributorFeeAmount = CONTRIBUTION_AMOUNT; // Contributor fee equals contribution (should fail)

        vm.prank(contributor1);
        vm.expectRevert(Aon.ContributorFeeCannotExceedContributionAmount.selector);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, contributorFeeAmount);
    }

    function test_Contribute_MultipleContributorFees_AccumulateCorrectly() public {
        uint256 contributionAmount1 = 1 ether;
        uint256 contributorFeeAmount1 = 0.1 ether;
        uint256 contributionAmount2 = 2 ether;
        uint256 contributorFeeAmount2 = 0.2 ether;

        // First contribution with contributor fee
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount1}(0, contributorFeeAmount1);

        // Second contribution with contributor fee
        vm.prank(contributor2);
        aon.contribute{value: contributionAmount2}(0, contributorFeeAmount2);

        assertEq(
            aon.totalContributorFee(),
            contributorFeeAmount1 + contributorFeeAmount2,
            "Total contributor fees should accumulate"
        );
        assertEq(
            aon.contributions(contributor1),
            contributionAmount1 - contributorFeeAmount1,
            "First contribution should exclude contributor fee"
        );
        assertEq(
            aon.contributions(contributor2),
            contributionAmount2 - contributorFeeAmount2,
            "Second contribution should exclude contributor fee"
        );
    }

    function test_ContributeFor_WithContributorFees_Success() public {
        uint256 contributorFeeAmount = PROCESSING_FEE;
        uint256 expectedContribution = CONTRIBUTION_AMOUNT - contributorFeeAmount;

        vm.prank(factoryOwner); // Factory calls contributeFor
        vm.expectEmit(true, true, true, true);
        emit ContributionReceived(contributor1, expectedContribution);
        aon.contributeFor{value: CONTRIBUTION_AMOUNT}(contributor1, 0, contributorFeeAmount);

        assertEq(address(aon).balance, CONTRIBUTION_AMOUNT, "Contract balance should include contributor fee");
        assertEq(aon.contributions(contributor1), expectedContribution, "Contribution should exclude contributor fee");
        assertEq(aon.totalContributorFee(), contributorFeeAmount, "Total contributor fee should be tracked");
    }
}

