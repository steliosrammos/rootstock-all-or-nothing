// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AonTestBase.sol";

contract AonRefundTest is AonTestBase {
    function test_SwipeFunds_ReentrancyAttack() public {
        // 1. Deploy attacker that will act as the factory owner
        MaliciousFactoryOwner attacker = new MaliciousFactoryOwner();

        // 2. Deploy a factory contract that designates the attacker as its owner
        MaliciousFactory factory = new MaliciousFactory(address(attacker));

        // 3. Deploy a new Aon instance for this test, via the malicious factory
        Aon implementation = new Aon();
        AonProxy proxy = new AonProxy(address(implementation));
        Aon aonForTest = Aon(address(proxy));
        vm.prank(address(factory)); // Pretend the factory is deploying this Aon instance
        // Set swipeRecipient to attacker address so funds go there and trigger reentrancy
        aonForTest.initialize(
            creator,
            GOAL,
            DURATION,
            address(goalReachedStrategy),
            30 days,
            30 days,
            feeRecipient,
            payable(address(attacker))
        );

        // 4. Link the attacker contract to the new Aon instance
        attacker.setAon(aonForTest);

        // 5. Fund the campaign and let it run its course until funds are swipe-able
        vm.prank(contributor1);
        aonForTest.contribute{value: 1 ether}(0, 0);
        vm.warp(aonForTest.endTime() + aonForTest.claimWindow() + aonForTest.refundWindow() + 1 days);

        // 6. Attacker tries to swipe funds, which triggers a re-entrant call.
        // The attack should fail because the contract becomes finalized after funds are sent,
        // preventing the cancel() call in the malicious receive() function.
        bytes memory innerError = abi.encodeWithSelector(Aon.CannotCancelFinalizedContract.selector);
        vm.expectRevert(abi.encodeWithSelector(Aon.FailedToSwipeFunds.selector, innerError));
        vm.prank(address(attacker));
        attacker.swipe();

        // 7. Check that the attack failed (which is good) - contract should not be cancelled
        assertEq(
            uint256(aonForTest.status()),
            uint256(Aon.Status.Active),
            "Attack should have failed and contract should remain active"
        );
    }

    function test_SwipeFunds_Success() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past all windows
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        uint256 contractBalance = address(aon).balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;
        uint256 swipeRecipientInitialBalance = swipeRecipient.balance;
        uint256 platformAmount = aon.totalContributorFee(); // 0 in this test
        uint256 recipientAmount = contractBalance - platformAmount;

        vm.prank(factoryOwner);
        vm.expectEmit(true, false, false, true);
        emit FundsSwiped(swipeRecipient, platformAmount, recipientAmount);
        aon.swipeFunds();

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + platformAmount,
            "Fee recipient should receive platform fees"
        );
        assertEq(
            swipeRecipient.balance,
            swipeRecipientInitialBalance + recipientAmount,
            "Swipe recipient should receive funds"
        );
    }

    function test_SwipeFunds_CanBeCalledByAnyone() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past all windows
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        uint256 contractBalance = address(aon).balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;
        uint256 swipeRecipientInitialBalance = swipeRecipient.balance;
        uint256 platformAmount = aon.totalContributorFee(); // 0 in this test
        uint256 recipientAmount = contractBalance - platformAmount;

        // Non-factory owner can swipe funds
        vm.prank(randomAddress);
        vm.expectEmit(true, false, false, true);
        emit FundsSwiped(swipeRecipient, platformAmount, recipientAmount);
        aon.swipeFunds();

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + platformAmount,
            "Fee recipient should receive platform fees"
        );
        assertEq(
            swipeRecipient.balance,
            swipeRecipientInitialBalance + recipientAmount,
            "Swipe recipient should receive funds"
        );
    }

    function test_SwipeFunds_FailsIfWindowNotOver() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        vm.warp(aon.endTime());

        vm.prank(factoryOwner);
        vm.expectRevert(Aon.CannotSwipeFundsBeforeEndOfClaimOrRefundWindow.selector);
        aon.swipeFunds();
    }

    function test_SwipeFunds_FailsIfNoFunds() public {
        // Fast-forward past all windows
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        vm.prank(factoryOwner);
        vm.expectRevert(Aon.NoFundsToSwipe.selector);
        aon.swipeFunds();
    }

    function test_SwipeFunds_WithUnclaimedContract_SendsPlatformFeesToFeeRecipient() public {
        // Contributors meet the goal
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past end time, claim window, and refund window (contract becomes unclaimed and swipeable)
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);
        assertTrue(aon.isUnclaimed(), "Contract should be unclaimed");

        uint256 contractBalance = address(aon).balance;
        uint256 claimableAmount = aon.claimableBalance();
        uint256 platformAmount =
            aon.isUnclaimed() ? aon.totalCreatorFee() + aon.totalContributorFee() : aon.totalContributorFee();
        uint256 recipientAmount = contractBalance - platformAmount;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;
        uint256 recipientInitialBalance = swipeRecipient.balance;

        vm.prank(factoryOwner);
        vm.expectEmit(true, false, false, true);
        emit FundsSwiped(swipeRecipient, platformAmount, recipientAmount);
        aon.swipeFunds();

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + platformAmount,
            "Fee recipient should receive platform fees"
        );
        assertEq(
            swipeRecipient.balance,
            recipientInitialBalance + claimableAmount,
            "Recipient should receive claimable amount"
        );
    }

    function test_SwipeFunds_WithUnclaimedContract_WithContributorFees() public {
        // Contributors meet the goal with contributor fees
        uint256 contributorFee = 0.1 ether;
        vm.prank(contributor1);
        aon.contribute{value: GOAL + contributorFee}(0, contributorFee);

        // Fast-forward past end time, claim window, and refund window (contract becomes unclaimed and swipeable)
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);
        assertTrue(aon.isUnclaimed(), "Contract should be unclaimed");

        uint256 contractBalance = address(aon).balance;
        uint256 claimableAmount = aon.claimableBalance();
        uint256 platformAmount = contractBalance - claimableAmount;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;
        uint256 recipientInitialBalance = swipeRecipient.balance;

        vm.prank(factoryOwner);
        aon.swipeFunds();

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + platformAmount,
            "Fee recipient should receive platform fees including contributor fees"
        );
        assertEq(
            swipeRecipient.balance,
            recipientInitialBalance + claimableAmount,
            "Recipient should receive claimable amount"
        );
        assertEq(platformAmount, aon.totalContributorFee(), "Platform amount should equal contributor fees");
    }

    function test_SwipeFunds_WithFailedContract_SendsAllToRecipient() public {
        // Contributors don't meet the goal
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past all windows
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Failed, "Contract should be failed");

        uint256 contractBalance = address(aon).balance;
        uint256 platformAmount =
            aon.isUnclaimed() ? aon.totalCreatorFee() + aon.totalContributorFee() : aon.totalContributorFee();
        uint256 recipientAmount = contractBalance - platformAmount;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;
        uint256 recipientInitialBalance = swipeRecipient.balance;

        vm.prank(factoryOwner);
        vm.expectEmit(true, false, false, true);
        emit FundsSwiped(swipeRecipient, platformAmount, recipientAmount);
        aon.swipeFunds();

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance,
            "Fee recipient should not receive anything for failed contracts"
        );
        assertEq(
            swipeRecipient.balance,
            recipientInitialBalance + contractBalance,
            "Recipient should receive all funds for failed contracts"
        );
    }

    function test_SwipeFunds_WithUnclaimedContract_NoPlatformFees() public {
        // Contributors meet the goal with no fees
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past end time, claim window, and refund window (contract becomes unclaimed and swipeable)
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);
        assertTrue(aon.isUnclaimed(), "Contract should be unclaimed");

        uint256 contractBalance = address(aon).balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;
        uint256 recipientInitialBalance = swipeRecipient.balance;

        vm.prank(factoryOwner);
        aon.swipeFunds();

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance,
            "Fee recipient should not receive anything when there are no platform fees"
        );
        assertEq(
            swipeRecipient.balance,
            recipientInitialBalance + contractBalance,
            "Recipient should receive all funds when there are no platform fees"
        );
    }

    function test_SwipeFunds_FailsIfClaimed() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);
        vm.prank(creator);
        aon.claim(0);

        // After claiming, balance is 0, so swipe will fail with NoFundsToSwipe
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);
        vm.prank(factoryOwner);
        vm.expectRevert(Aon.NoFundsToSwipe.selector);
        aon.swipeFunds();
    }

    function test_SwipeFunds_AtWindowBoundary() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow());

        // Should fail exactly at boundary (must be after)
        vm.prank(factoryOwner);
        vm.expectRevert(Aon.CannotSwipeFundsBeforeEndOfClaimOrRefundWindow.selector);
        aon.swipeFunds();

        // Should succeed 1 second after boundary
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1);
        vm.prank(factoryOwner);
        aon.swipeFunds();
        assertEq(address(aon).balance, 0, "Contract balance should be zero");
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
}
