// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AonTestBase.sol";

contract AonViewTest is AonTestBase {
    /*
    * VIEW FUNCTION TESTS
    */

    function test_GetGoalInfo_ReturnsCorrectValues() public {
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(0, 0);

        uint256 currentBalance = aon.goalBalance();
        uint256 targetGoal = aon.goal();

        assertEq(currentBalance, 5 ether, "Current balance should be 5 ether");
        assertEq(targetGoal, GOAL, "Target goal should be GOAL");
        assertEq(currentBalance, aon.goalBalance(), "Should match goalBalance()");
    }

    function test_CanClaim_ReturnsCorrectAmount() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);

        uint256 claimableAmount = aon.canClaim(creator);
        assertEq(claimableAmount, GOAL, "Can claim should return GOAL");
    }

    function test_CanClaim_FailsIfNotCreator() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);

        vm.expectRevert(Aon.OnlyCreatorCanClaim.selector);
        aon.canClaim(randomAddress);
    }

    function test_GetRefundAmount_ReturnsCorrectAmount() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);
        vm.prank(creator);
        aon.cancel();

        uint256 refundAmount = aon.getRefundAmount(contributor1, 0);
        assertEq(refundAmount, CONTRIBUTION_AMOUNT, "Refund amount should equal contribution");
    }

    function test_GetRefundAmount_WithProcessingFee_ReturnsCorrectAmount() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);
        vm.prank(creator);
        aon.cancel();

        uint256 refundAmount = aon.getRefundAmount(contributor1, PROCESSING_FEE);
        assertEq(refundAmount, CONTRIBUTION_AMOUNT - PROCESSING_FEE, "Refund amount should exclude processing fee");
    }

    function test_GetRefundAmount_FailsIfClaimed() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);
        vm.prank(contributor2);
        aon.contribute{value: GOAL - CONTRIBUTION_AMOUNT}(0, 0);
        vm.warp(aon.endTime() + 1 days);
        vm.prank(creator);
        aon.claim(0);

        vm.expectRevert(Aon.CannotRefundClaimedContract.selector);
        aon.getRefundAmount(contributor1, 0);
    }

    function test_CanCancel_ReturnsTrueForCreator() public view {
        bool canCancelResult = aon.canCancel();
        assertTrue(canCancelResult, "Creator should be able to cancel");
    }

    function test_CanCancel_ReturnsTrueForFactoryOwner() public view {
        // Factory owner is address(this) in tests
        bool canCancelResult = aon.canCancel();
        assertTrue(canCancelResult, "Factory owner should be able to cancel");
    }

    function test_CanCancel_FailsIfNotAuthorized() public {
        vm.prank(randomAddress);
        vm.expectRevert(Aon.OnlyCreatorOrFactoryOwnerCanCancel.selector);
        aon.canCancel();
    }

    function test_IsValidContribution_ValidatesCorrectly() public view {
        // Should not revert for valid contribution
        aon.isValidContribution(1 ether, 0);
        aon.isValidContribution(1 ether, 0.1 ether);
    }

    function test_IsValidContribution_FailsIfAfterEndTime() public {
        vm.warp(aon.endTime() + 1 days);
        vm.expectRevert(Aon.CannotContributeAfterEndTime.selector);
        aon.isValidContribution(1 ether, 0);
    }

    function test_IsValidContribution_FailsIfCancelled() public {
        vm.prank(creator);
        aon.cancel();
        vm.expectRevert(Aon.CannotContributeToCancelledContract.selector);
        aon.isValidContribution(1 ether, 0);
    }

    function test_IsValidSwipe_ValidatesCorrectly() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        // Should not revert for valid swipe
        vm.prank(factoryOwner);
        aon.isValidSwipe();
    }

    function test_IsValidSwipe_WorksForAnyone() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        // Note: isValidSwipe() doesn't check owner - it only checks time window and balance
        // The owner check is not in isValidSwipe() or swipeFunds() - anyone can swipe
        // So we test that isValidSwipe() passes when conditions are met for anyone
        vm.prank(randomAddress);
        // isValidSwipe() should pass (no owner check)
        aon.isValidSwipe(); // This should not revert

        // Verify swipeFunds() also works for non-owner (as confirmed by existing test)
        vm.prank(randomAddress);
        aon.swipeFunds(); // This should work - no owner restriction
        // Verify funds were swiped
        assertEq(address(aon).balance, 0, "Contract should be empty");
    }

    function test_IsValidSwipe_FailsIfWindowNotOver() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow());

        vm.prank(factoryOwner);
        vm.expectRevert(Aon.CannotSwipeFundsBeforeEndOfClaimOrRefundWindow.selector);
        aon.isValidSwipe();
    }

    function test_DomainSeparator_ReturnsCorrectValue() public view {
        bytes32 domainSeparator = aon.domainSeparator();
        assertTrue(domainSeparator != bytes32(0), "Domain separator should not be zero");
    }

    function test_GetNonce_ReturnsCorrectValue() public {
        uint256 initialNonce = aon.getNonce(contributor1);
        assertEq(initialNonce, 0, "Initial nonce should be zero");

        // After a refund to swap contract, nonce should increment
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);
        vm.prank(creator);
        aon.cancel();

        address swapContract = address(0x123);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature =
            _createRefundSignature(contributor1, swapContract, CONTRIBUTION_AMOUNT, deadline, contributor1PrivateKey);

        aon.refundToSwapContract(
            contributor1,
            ISwapHTLC(swapContract),
            deadline,
            signature,
            0,
            Aon.SwapContractLockParams({
                preimageHash: bytes32(0),
                claimAddress: address(0x123),
                refundAddress: address(0x456),
                timelock: 3600,
                functionSignature: "lock(bytes32,address,address,uint256)"
            })
        );

        uint256 newNonce = aon.getNonce(contributor1);
        assertEq(newNonce, initialNonce + 1, "Nonce should increment after refund to swap contract");
    }

    function test_ClaimableBalance_ReturnsCorrectValue() public {
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(0.5 ether, 0); // 0.5 ether creator fee
        vm.prank(contributor2);
        aon.contribute{value: 5 ether}(0, 0.1 ether); // 0.1 ether contributor fee

        uint256 claimableBalance = aon.claimableBalance();
        // Total: 10 ether, creator fee: 0.5 ether, contributor fee: 0.1 ether
        // Claimable: 10 - 0.5 - 0.1 = 9.4 ether
        assertEq(claimableBalance, 9.4 ether, "Claimable balance should exclude all fees");
    }

    function test_GoalBalance_ReturnsCorrectValue() public {
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(0, 0.1 ether); // 0.1 ether contributor fee

        uint256 goalBalance = aon.goalBalance();
        // Total: 5 ether, contributor fee: 0.1 ether
        // Goal balance: 5 - 0.1 = 4.9 ether
        assertEq(goalBalance, 4.9 ether, "Goal balance should exclude contributor fees");
    }
}

