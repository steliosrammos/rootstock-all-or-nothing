// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AonTestBase.sol";

contract AonRefundTest is AonTestBase {
    /*
    * REFUND TESTS
    */

    function test_Refund_SuccessIfCampaignFailed() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        vm.warp(aon.endTime() + 1 days); // Let campaign fail
        assertTrue(aon.getStatus() == Aon.Status.Failed, "Campaign should have failed");

        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit ContributionRefunded(contributor1, CONTRIBUTION_AMOUNT);
        aon.refund(0);

        assertEq(
            contributor1.balance, contributorInitialBalance + CONTRIBUTION_AMOUNT, "Contributor should get money back"
        );
        (uint128 amount,) = aon.contributions(contributor1);
        assertEq(amount, 0, "Contribution record should be cleared");
    }

    function test_Refund_SuccessIfCancelled() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        vm.prank(creator);
        aon.cancel();

        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund(0);
        assertEq(
            contributor1.balance, contributorInitialBalance + CONTRIBUTION_AMOUNT, "Contributor should get money back"
        );
    }

    function test_Refund_WithProcessingFee_Success() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        vm.prank(creator);
        aon.cancel();

        uint256 contributorInitialBalance = contributor1.balance;
        uint256 initialTotalContributorFee = aon.totalContributorFee();
        uint256 initialFeeRecipientBalance = feeRecipient.balance;

        vm.prank(contributor1);
        aon.refund(PROCESSING_FEE);
        assertEq(
            contributor1.balance,
            contributorInitialBalance + CONTRIBUTION_AMOUNT - PROCESSING_FEE,
            "Contributor should get money back"
        );
        assertEq(aon.totalContributorFee(), initialTotalContributorFee, "Total contributor fee should not change");
        assertEq(
            feeRecipient.balance,
            initialFeeRecipientBalance + PROCESSING_FEE,
            "Fee recipient should receive the processing fee"
        );
    }

    function test_Refund_WithProcessingFee_Failure() public {
        uint256 processingFee = 1.1 ether;
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        vm.prank(creator);
        aon.cancel();

        vm.prank(contributor1);
        vm.expectRevert(
            abi.encodeWithSelector(Aon.ProcessingFeeHigherThanRefundAmount.selector, CONTRIBUTION_AMOUNT, processingFee)
        );
        aon.refund(processingFee);
    }

    function test_Refund_SuccessIfUnclaimed() public {
        uint256 contributionAmount = GOAL;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        // Fast-forward past claim window
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);

        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund(0);
        assertEq(
            contributor1.balance, contributorInitialBalance + contributionAmount, "Contributor should get money back"
        );
    }

    function test_Refund_FailsWhenGoalReachedAndWithinClaimWindow() public {
        // Contribute enough to reach the goal
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past endTime but still within claim window
        vm.warp(aon.endTime() + 1 days);

        // Verify status is Successful (goal reached, within claim window)
        assertTrue(aon.getStatus() == Aon.Status.Successful, "Campaign should be successful");

        // Attempt to refund should fail
        vm.prank(contributor1);
        vm.expectRevert(Aon.CannotRefundDuringClaimWindow.selector);
        aon.refund(0);
    }

    function test_Refund_SuccessWhenBalanceDropsBelowGoalAfterCampaignEnd() public {
        // Setup: Goal is reached
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Another contributor adds a bit more
        vm.prank(contributor2);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past claim window (contract becomes unclaimed)
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);
        assertTrue(aon.goalBalance() >= GOAL, "Balance should be at or above goal initially");

        // First refund: contributor1 refunds their GOAL amount
        // This will drop balance below goal, but should set status to Unclaimed
        uint256 contributor1InitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund(0);

        // Verify first refund succeeded
        assertEq(contributor1.balance, contributor1InitialBalance + GOAL, "First contributor should get money back");

        // Verify balance is now below goal
        assertTrue(aon.goalBalance() < GOAL, "Balance should be below goal after first refund");

        // Second refund: contributor2 should still be able to refund
        // even though balance is below goal, because status is Unclaimed
        uint256 contributor2InitialBalance = contributor2.balance;
        vm.prank(contributor2);
        aon.refund(0);

        // Verify second refund succeeded
        assertEq(
            contributor2.balance,
            contributor2InitialBalance + 1 ether,
            "Second contributor should get money back even though balance is below goal"
        );
    }

    function test_Refund_FailsForZeroContribution() public {
        vm.prank(creator);
        aon.cancel(); // Allow refunds

        vm.prank(contributor1); // Contributor1 has 0 contribution
        vm.expectRevert(Aon.CannotRefundZeroContribution.selector);
        aon.refund(0);
    }

    function test_Refund_FailsIfItDropsBalanceBelowGoal() public {
        vm.prank(contributor1);
        uint256 contributionAmount = GOAL;
        aon.contribute{value: contributionAmount}(0, 0); // Exactly meets goal

        // Another contribution
        vm.prank(contributor2);
        aon.contribute{value: 1 ether}(0, 0);

        // Contributor 1 cannot refund because it would bring balance below goal
        vm.prank(contributor1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Aon.RefundWouldDropBalanceBelowGoal.selector, address(aon).balance, contributionAmount, GOAL
            )
        );
        aon.refund(0);
    }

    function test_Refund_WithContributorFees_ContributorFeesNotRefunded() public {
        uint256 contributorFeeAmount = PROCESSING_FEE;
        uint256 expectedRefund = CONTRIBUTION_AMOUNT - contributorFeeAmount;

        // Contribute with contributor fee
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, contributorFeeAmount);

        // Let campaign fail
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Failed, "Campaign should have failed");

        uint256 contributorInitialBalance = contributor1.balance;
        uint256 factoryInitialBalance = factoryOwner.balance;

        // Refund should only return contribution amount, not contributor fee
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit ContributionRefunded(contributor1, expectedRefund);
        aon.refund(0);

        assertEq(
            contributor1.balance,
            contributorInitialBalance + expectedRefund,
            "Contributor should get contribution back (not contributor fee)"
        );
        assertEq(factoryOwner.balance, factoryInitialBalance, "Factory should not receive contributor fees on refund");
        (uint128 amount,) = aon.contributions(contributor1);
        assertEq(amount, 0, "Contribution record should be cleared");
        assertEq(aon.totalContributorFee(), contributorFeeAmount, "Total contributor fee should remain unchanged");
    }

    function test_Refund_WithContributorFees_AfterCancellation_ContributorFeesNotRefunded() public {
        uint256 contributorFeeAmount = PROCESSING_FEE;
        uint256 expectedRefund = CONTRIBUTION_AMOUNT - contributorFeeAmount;

        // Contribute with contributor fee
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, contributorFeeAmount);

        // Cancel campaign
        vm.prank(creator);
        aon.cancel();

        uint256 contributorInitialBalance = contributor1.balance;
        uint256 factoryInitialBalance = factoryOwner.balance;

        // Refund should only return contribution amount, not contributor fee
        vm.prank(contributor1);
        aon.refund(0);

        assertEq(
            contributor1.balance,
            contributorInitialBalance + expectedRefund,
            "Contributor should get contribution back (not contributor fee)"
        );
        assertEq(factoryOwner.balance, factoryInitialBalance, "Factory should not receive contributor fees on refund");
        assertEq(aon.totalContributorFee(), contributorFeeAmount, "Total contributor fee should remain unchanged");
    }

    function test_Refund_FailsIfClaimed() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);
        vm.prank(contributor2);
        aon.contribute{value: GOAL - CONTRIBUTION_AMOUNT}(0, 0);
        vm.warp(aon.endTime() + 1 days);
        vm.prank(creator);
        aon.claim(0);

        vm.prank(contributor1);
        vm.expectRevert(Aon.CannotRefundClaimedContract.selector);
        aon.refund(0);
    }

    function test_Refund_SuccessWhenActiveBeforeGoalReached() public {
        // Contribute but don't reach goal yet
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        // Before end time, goal not reached - should be able to refund
        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund(0);

        assertEq(
            contributor1.balance,
            contributorInitialBalance + CONTRIBUTION_AMOUNT,
            "Contributor should get money back even when active"
        );
        (uint128 amount,) = aon.contributions(contributor1);
        assertEq(amount, 0, "Contribution record should be cleared");
    }

    function test_Refund_MultipleRefundsBySameContributor() public {
        // Contribute multiple times
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        vm.prank(contributor1);
        aon.contribute{value: 2 ether}(0, 0);

        (uint128 totalContribution,) = aon.contributions(contributor1);
        assertEq(totalContribution, 3 ether, "Total contribution should be 3 ether");

        // Cancel to allow refund
        vm.prank(creator);
        aon.cancel();

        // Refund should return all contributions
        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund(0);

        assertEq(
            contributor1.balance, contributorInitialBalance + 3 ether, "Contributor should get all contributions back"
        );
        (uint128 amountAfterRefund,) = aon.contributions(contributor1);
        assertEq(amountAfterRefund, 0, "Contribution record should be cleared");
    }

    /*
    * REENTRANCY TESTS
    */

    function test_Refund_ReentrancyGuard() public {
        // Setup attacker contract
        MaliciousRefund attacker = new MaliciousRefund(aon);
        vm.deal(address(attacker), 1 ether);

        // Attacker contributes
        attacker.contribute{value: 1 ether}(0, 0);
        (uint128 attackerContribution,) = aon.contributions(address(attacker));
        assertEq(attackerContribution, 1 ether);

        // Cancel campaign to allow refunds
        vm.prank(creator);
        aon.cancel();

        // We expect the refund to fail with our new nested error.
        // The outer error is `FailedToRefund`, and its `reason` payload
        // is the bytes of the inner `CannotRefundZeroContribution` error.
        bytes memory innerError = abi.encodeWithSelector(Aon.CannotRefundZeroContribution.selector);
        vm.expectRevert(abi.encodeWithSelector(Aon.FailedToRefund.selector, innerError));
        attacker.startAttack();
    }

    function test_RefundToSwapContract_Success() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        // Cancel campaign to allow refunds
        vm.prank(creator);
        aon.cancel();

        // Create signature for refund
        address swapContract = address(0x123);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 preimageHash = bytes32(0);
        address claimAddress = address(0x123);
        address refundAddress = address(0x456);
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", preimageHash, claimAddress, refundAddress, 3600
        );

        uint256 initialNonce = aon.nonces(contributor1);

        bytes memory signature = _createRefundSignatureWithLockCallData(
            contributor1,
            swapContract,
            CONTRIBUTION_AMOUNT,
            deadline,
            processingFee,
            lockCallData,
            contributor1PrivateKey
        );

        uint256 swapContractInitialBalance = swapContract.balance;

        // Execute refund with signature
        vm.expectEmit(true, true, true, true);
        emit ContributionRefunded(contributor1, CONTRIBUTION_AMOUNT);
        aon.refundToSwapContract(
            contributor1, ISwapHTLC(swapContract), processingFee, lockCallData, signature, deadline
        );

        // Verify refund was successful
        assertEq(
            swapContract.balance,
            swapContractInitialBalance + CONTRIBUTION_AMOUNT,
            "Swap contract should receive refund"
        );
        (uint128 amount,) = aon.contributions(contributor1);
        assertEq(amount, 0, "Contribution should be cleared");
        assertEq(aon.nonces(contributor1), initialNonce + 1, "Nonce should be incremented");
    }

    function test_RefundToSwapContract_WithProcessingFee_Success() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        uint256 expectedRefund = CONTRIBUTION_AMOUNT - PROCESSING_FEE;

        // Cancel campaign to allow refunds
        vm.prank(creator);
        aon.cancel();

        // Create signature for refund
        address swapContract = address(0x123);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = aon.nonces(contributor1);
        uint256 initialTotalContributorFee = aon.totalContributorFee();

        uint256 initialFeeRecipientBalance = feeRecipient.balance;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", bytes32(0), address(0x123), address(0x456), 3600
        );

        bytes memory signature = _createRefundSignatureWithLockCallData(
            contributor1, swapContract, expectedRefund, deadline, PROCESSING_FEE, lockCallData, contributor1PrivateKey
        );

        // Execute refund with signature
        vm.expectEmit(true, true, true, true);
        emit ContributionRefunded(contributor1, expectedRefund);
        aon.refundToSwapContract(
            contributor1, ISwapHTLC(swapContract), PROCESSING_FEE, lockCallData, signature, deadline
        );

        // Verify refund was successful
        assertEq(swapContract.balance, expectedRefund, "Swap contract should receive refund");
        (uint128 amount,) = aon.contributions(contributor1);
        assertEq(amount, 0, "Contribution should be cleared");
        assertEq(aon.nonces(contributor1), nonce + 1, "Nonce should be incremented");
        assertEq(aon.totalContributorFee(), initialTotalContributorFee, "Total contributor fee should not change");
        assertEq(
            feeRecipient.balance,
            initialFeeRecipientBalance + PROCESSING_FEE,
            "Fee recipient should receive the processing fee"
        );
    }

    function test_RefundToSwapContract_FailsWithInvalidSignature() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        vm.prank(creator);
        aon.cancel();

        address swapContract = address(0x123);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", bytes32(0), address(0x123), address(0x456), 3600
        );

        bytes memory signature = _createRefundSignatureWithLockCallData(
            contributor1,
            swapContract,
            CONTRIBUTION_AMOUNT,
            deadline,
            processingFee,
            lockCallData,
            contributor1PrivateKey
        );
        // Sign with wrong private key (contributor2's key instead of contributor1's)
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Refund(address contributor,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 lockCallDataHash)"
                ),
                contributor1,
                swapContract,
                CONTRIBUTION_AMOUNT,
                aon.nonces(contributor1),
                deadline,
                processingFee,
                keccak256(lockCallData)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(2, keccak256(abi.encodePacked("\x19\x01", aon.domainSeparator(), structHash))); // contributor2 uses key index 2
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(Aon.InvalidSignature.selector);
        aon.refundToSwapContract(
            contributor1, ISwapHTLC(swapContract), processingFee, lockCallData, wrongSignature, deadline
        );
    }

    function test_RefundToSwapContract_FailsWithExpiredSignature() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        vm.prank(creator);
        aon.cancel();

        address swapContract = address(0x123);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 preimageHash = bytes32(0);
        address claimAddress = address(0x123);
        address refundAddress = address(0x456);
        uint256 timelock = 3600;
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", preimageHash, claimAddress, refundAddress, timelock
        );

        bytes memory signature = _createRefundSignatureWithLockCallData(
            contributor1,
            swapContract,
            CONTRIBUTION_AMOUNT,
            deadline,
            processingFee,
            lockCallData,
            contributor1PrivateKey
        );

        // Fast-forward past the deadline
        vm.warp(deadline + 1);

        vm.expectRevert(Aon.SignatureExpired.selector);
        aon.refundToSwapContract(
            contributor1, ISwapHTLC(swapContract), processingFee, lockCallData, signature, deadline
        );
    }

    function test_RefundToSwapContract_FailsWithInvalidSwapContract() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);

        vm.prank(creator);
        aon.cancel();

        uint256 deadline = block.timestamp + 1 hours;
        address swapContract = address(0);
        bytes32 preimageHash = bytes32(0);
        address claimAddress = address(0x123);
        address refundAddress = address(0x456);
        uint256 timelock = 3600;
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", preimageHash, claimAddress, refundAddress, timelock
        );
        bytes memory signature = new bytes(65);

        vm.expectRevert(Aon.InvalidSwapContract.selector);
        aon.refundToSwapContract(
            contributor1, ISwapHTLC(swapContract), processingFee, lockCallData, signature, deadline
        );
    }

    function test_RefundToSwapContract_VerifiesParameterOrder() public {
        vm.prank(contributor1);
        aon.contribute{value: CONTRIBUTION_AMOUNT}(0, 0);
        vm.prank(creator);
        aon.cancel();

        MockSwapHTLC mockSwap = new MockSwapHTLC();
        bytes32 preimageHash = bytes32(uint256(0x5678));
        address claimAddress = address(0x123);
        address refundAddress = address(0x456);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 timelock = 3600;
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", preimageHash, claimAddress, refundAddress, timelock
        );

        bytes memory signature = _createRefundSignatureWithLockCallData(
            contributor1,
            address(mockSwap),
            CONTRIBUTION_AMOUNT,
            deadline,
            processingFee,
            lockCallData,
            contributor1PrivateKey
        );

        aon.refundToSwapContract(
            contributor1, ISwapHTLC(address(mockSwap)), processingFee, lockCallData, signature, deadline
        );

        assertEq(mockSwap.lastPreimageHash(), preimageHash, "Preimage hash should match");
        assertEq(mockSwap.lastClaimAddress(), claimAddress, "Claim address should match");
        assertEq(mockSwap.lastRefundAddress(), refundAddress, "Refund address should match");
        assertEq(mockSwap.lastTimelock(), 3600, "Timelock should match");
    }
}
