// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AonTestBase.sol";

contract AonClaimTest is AonTestBase {
    /*
    * CLAIM TESTS (SUCCESSFUL CAMPAIGN)
    */

    function test_Claim_Success() public {
        // Contributors meet the goal
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(0, 0);
        vm.prank(contributor2);
        aon.contribute{value: 5 ether}(0, 0);

        // Fast-forward past the end time
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Successful, "Campaign should be successful");

        // Creator claims the funds
        uint256 processingFee = 0;
        // creatorAmount is calculated after processingFee is added to totalCreatorFee in claim()
        // So we need to account for that: creatorAmount = claimableBalance() - processingFee
        uint256 creatorAmount = aon.claimableBalance() - processingFee;
        uint256 totalFee = aon.totalCreatorFee() + aon.totalContributorFee() + processingFee;
        uint256 creatorInitialBalance = creator.balance;
        uint256 factoryInitialBalance = factoryOwner.balance;

        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true);
        emit Claimed(creatorAmount, aon.totalCreatorFee() + processingFee, aon.totalContributorFee());
        aon.claim(processingFee);
        vm.stopPrank();

        assertEq(address(aon).balance, 0, "Contract balance should be zero after claim");
        assertEq(creator.balance, creatorInitialBalance + creatorAmount, "Creator should receive the funds");
        assertEq(factoryOwner.balance, factoryInitialBalance + totalFee, "Factory should receive the fee");
    }

    function test_Claim_WithContributorFees_Failure() public {
        // Contributors meet the goal with contributor fees, but goal is not reached
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(0, 0.5 ether); // 4.5 ether contribution, 0.5 ether contributor fee
        vm.prank(contributor2);
        aon.contribute{value: 5 ether}(0, 0.5 ether); // 4.5 ether contribution, 0.5 ether contributor fee

        // Fast-forward past the end time
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Failed, "Campaign should have failed");
    }

    function test_Claim_WithContributorFees_Success() public {
        // Contributors meet the goal with contributor fees
        vm.prank(contributor1);
        aon.contribute{value: 6 ether}(0, 0.5 ether); // 5.5 ether contribution, 0.5 ether contributor fee
        vm.prank(contributor2);
        aon.contribute{value: 6 ether}(0, 0.5 ether); // 5.5 ether contribution, 0.5 ether contributor fee

        // Fast-forward past the end time
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Successful, "Campaign should be successful");

        // Creator claims the funds
        uint256 processingFee = 0;
        // creatorAmount is calculated after processingFee is added to totalCreatorFee in claim()
        // So we need to account for that: creatorAmount = claimableBalance() - processingFee
        uint256 creatorAmount = aon.claimableBalance() - processingFee;
        uint256 totalFee = aon.totalCreatorFee() + aon.totalContributorFee() + processingFee;
        uint256 creatorInitialBalance = creator.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true);
        emit Claimed(creatorAmount, aon.totalCreatorFee() + processingFee, aon.totalContributorFee());
        aon.claim(processingFee);
        vm.stopPrank();

        assertEq(address(aon).balance, 0, "Contract balance should be zero after claim");
        assertEq(
            creator.balance,
            creatorInitialBalance + creatorAmount,
            "Creator should receive the funds (excluding contributor fees)"
        );
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + totalFee,
            "Fee recipient should receive fees and contributor fees"
        );
    }

    function test_Claim_WithProcessingFee_Success() public {
        // Contributors meet the goal
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(0, 0);
        vm.prank(contributor2);
        aon.contribute{value: 5 ether}(0, 0);

        // Fast-forward past the end time
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Successful, "Campaign should be successful");

        // Creator claims the funds with processing fee
        uint256 processingFee = PROCESSING_FEE;
        // creatorAmount is calculated after processingFee is added to totalCreatorFee in claim()
        // So we need to account for that: creatorAmount = claimableBalance() - processingFee
        uint256 creatorAmount = aon.claimableBalance() - processingFee;
        uint256 totalFee = aon.totalCreatorFee() + aon.totalContributorFee() + processingFee;
        uint256 creatorInitialBalance = creator.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true);
        emit Claimed(creatorAmount, aon.totalCreatorFee() + processingFee, aon.totalContributorFee());
        aon.claim(processingFee);
        vm.stopPrank();

        assertEq(address(aon).balance, 0, "Contract balance should be zero after claim");
        assertEq(creator.balance, creatorInitialBalance + creatorAmount, "Creator should receive the funds");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + totalFee,
            "Fee recipient should receive the fee including processing fee"
        );
        assertEq(aon.totalCreatorFee(), processingFee, "Total creator fee should equal processing fee");
    }

    function test_Claim_FailsIfNotCreator() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);

        vm.prank(randomAddress);
        vm.expectRevert(Aon.OnlyCreatorCanClaim.selector);
        aon.claim(0);
    }

    function test_Claim_FailsIfGoalNotReached() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL - 1 ether}(0, 0);
        vm.warp(aon.endTime() + 1 days);

        vm.prank(creator);
        vm.expectRevert(Aon.CannotClaimFailedContract.selector);
        aon.claim(0);
    }

    function test_Claim_FailsIfCampaignFailed() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0); // Goal not reached

        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Failed, "Campaign should have failed");

        vm.prank(creator);
        vm.expectRevert(Aon.CannotClaimFailedContract.selector);
        aon.claim(0);
    }

    function test_Claim_FailsIfCancelled() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.prank(creator);
        aon.cancel();

        vm.prank(creator);
        vm.expectRevert(Aon.CannotClaimCancelledContract.selector);
        aon.claim(0);
    }

    function test_Claim_FailsIfAlreadyClaimed() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);
        vm.prank(creator);
        aon.claim(0);

        vm.prank(creator);
        vm.expectRevert(Aon.AlreadyClaimed.selector);
        aon.claim(0);
    }

    function test_Claim_FailsAfterClaimWindow() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);

        vm.prank(creator);
        vm.expectRevert(Aon.CannotClaimAfterClaimWindow.selector);
        aon.claim(0);
    }

    function test_Claim_WithCreatorFee_Success() public {
        uint128 creatorFeeAmount = 0.5 ether;
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(creatorFeeAmount, 0);
        vm.prank(contributor2);
        aon.contribute{value: 5 ether}(creatorFeeAmount, 0);

        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Successful, "Campaign should be successful");

        uint256 processingFee = 0;
        uint256 creatorAmount = aon.claimableBalance() - processingFee;
        uint256 totalFee = aon.totalCreatorFee() + aon.totalContributorFee() + processingFee;
        uint256 creatorInitialBalance = creator.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true);
        emit Claimed(creatorAmount, aon.totalCreatorFee() + processingFee, aon.totalContributorFee());
        aon.claim(processingFee);
        vm.stopPrank();

        assertEq(address(aon).balance, 0, "Contract balance should be zero after claim");
        assertEq(creator.balance, creatorInitialBalance + creatorAmount, "Creator should receive the funds");
        assertEq(
            feeRecipient.balance, feeRecipientInitialBalance + totalFee, "Fee recipient should receive creator fees"
        );
    }

    function test_Claim_TotalCreatorFeeCorrectAfterRefund() public {
        // Scenario: 2 contributions with creator fees, 1 is refunded
        // totalCreatorFee SHOULD decrease after refund - fees from refunded contributions are returned
        uint128 creatorFee1 = 0.1 ether;
        uint128 creatorFee2 = 0.2 ether;
        uint256 contributionAmount1 = 5 ether;
        uint256 contributionAmount2 = 11 ether; // Large enough so goal stays reached after refund

        // Contribution 1: 5 ETH with 0.1 ETH creator fee
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount1}(creatorFee1, 0);
        assertEq(aon.totalCreatorFee(), creatorFee1, "Creator fee should be 0.1 ETH after first contribution");

        // Contribution 2: 11 ETH with 0.2 ETH creator fee
        vm.prank(contributor2);
        aon.contribute{value: contributionAmount2}(creatorFee2, 0);
        assertEq(
            aon.totalCreatorFee(), creatorFee1 + creatorFee2, "Creator fee should be 0.3 ETH after second contribution"
        );

        // Contributor 1 refunds
        // Goal still reached: goalBalance after refund = 11 - 0.2 = 10.8 ETH >= 10 ETH goal
        vm.prank(contributor1);
        aon.refund(0);

        // totalCreatorFee SHOULD be reduced by creatorFee1 (0.1 ETH) after refund
        assertEq(
            aon.totalCreatorFee(),
            creatorFee2,
            "Creator fee should be 0.2 ETH after refund - fee from refunded contribution should be deducted"
        );

        // Move to claim window
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Successful, "Campaign should be successful");

        uint256 processingFee = 0;
        uint256 expectedTotalCreatorFee = creatorFee2 + processingFee; // Only fee from non-refunded contribution
        uint256 creatorInitialBalance = creator.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        // Creator claims
        vm.prank(creator);
        aon.claim(processingFee);

        // Verify totalCreatorFee in contract state (only from remaining contribution)
        assertEq(
            aon.totalCreatorFee(),
            expectedTotalCreatorFee,
            "Total creator fee should only include fee from non-refunded contribution"
        );

        // Verify fee recipient received only the creator fee from non-refunded contribution
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + expectedTotalCreatorFee,
            "Fee recipient should only receive creator fee from non-refunded contribution"
        );

        // Verify creator received the remaining balance
        // Contract balance after refund: 11 ETH
        // Creator gets: 11 ETH - 0.2 ETH (totalCreatorFee) = 10.8 ETH
        uint256 expectedCreatorAmount = contributionAmount2 - expectedTotalCreatorFee;
        assertEq(
            creator.balance,
            creatorInitialBalance + expectedCreatorAmount,
            "Creator should receive contribution minus remaining creator fee"
        );
    }

    function test_Claim_AtClaimWindowBoundary() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + aon.claimWindow());

        // Should still be able to claim at the exact boundary
        vm.prank(creator);
        aon.claim(0);
        assertEq(uint256(aon.status()), uint256(Aon.Status.Claimed), "Status should be Claimed");
    }

    function test_Claim_WithZeroClaimableBalance() public {
        // Contribute with creator fees almost equal to the contribution
        // This creates a scenario where claimableBalance is very small (near 0)
        // We can't use GOAL as fee because fee must be < amount, so use GOAL - 1 wei
        uint128 creatorFee = uint128(GOAL - 1);
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(creatorFee, 0); // Almost all goes to creator fee

        vm.warp(aon.endTime() + 1 days);
        // claimableBalance = address(this).balance - totalCreatorFee - totalContributorFee
        // = GOAL - (GOAL - 1) - 0 = 1 wei
        assertEq(aon.claimableBalance(), 1, "Claimable balance should be 1 wei");

        uint256 creatorInitialBalance = creator.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.prank(creator);
        aon.claim(0);

        // Creator should receive 1 wei, fee recipient should receive the creator fee
        assertEq(creator.balance, creatorInitialBalance + 1, "Creator should receive 1 wei");
        assertEq(
            feeRecipient.balance, feeRecipientInitialBalance + creatorFee, "Fee recipient should receive creator fee"
        );
        assertEq(address(aon).balance, 0, "Contract balance should be zero");
    }

    /*
    * CLAIM TO SWAP CONTRACT TESTS
    */

    function test_ClaimToSwapContract_Success() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.getStatus() == Aon.Status.Successful, "Campaign should be successful");

        address swapContract = address(0x456);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 claimAmount = aon.claimableBalance();

        address claimAddress = address(0x456);
        address refundAddress = address(0x789);
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", bytes32(0), claimAddress, refundAddress, 7200
        );

        bytes memory signature = _createClaimSignature(swapContract, claimAmount, deadline, processingFee, lockCallData);

        uint256 initialNonce = aon.nonces(creator);
        uint256 initialSwapBalance = swapContract.balance;

        vm.expectEmit(true, true, true, true);
        emit Claimed(claimAmount, aon.totalCreatorFee(), aon.totalContributorFee());
        aon.claimToSwapContract(ISwapHTLC(swapContract), processingFee, lockCallData, signature, deadline);

        assertEq(swapContract.balance, initialSwapBalance + claimAmount, "Swap contract should receive creator amount");
        assertEq(aon.nonces(creator), initialNonce + 1, "Nonce should be incremented");
        assertEq(uint256(aon.status()), uint256(Aon.Status.Claimed), "Status should be Claimed");
    }

    function test_ClaimToSwapContract_FailsWithInvalidSignature() public {
        uint256 contributionAmount = GOAL;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        // Fast-forward past the campaign end time
        vm.warp(aon.endTime() + 1 days);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 claimAmount = address(aon).balance;
        address swapContract = address(0x456);
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", bytes32(0), address(0x456), address(0x789), 7200
        );

        bytes memory signature = _createClaimSignature(swapContract, claimAmount, deadline, processingFee, lockCallData);
        // Sign with wrong private key (contributor1's key instead of creator's)
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 lockCallDataHash)"
                ),
                creator,
                swapContract,
                claimAmount,
                aon.nonces(creator),
                deadline,
                processingFee,
                keccak256(lockCallData)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(contributor1PrivateKey, keccak256(abi.encodePacked("\x19\x01", aon.domainSeparator(), structHash)));

        vm.expectRevert(Aon.InvalidSignature.selector);
        aon.claimToSwapContract(
            ISwapHTLC(swapContract), processingFee, lockCallData, abi.encodePacked(r, s, v), deadline
        );
    }

    function test_ClaimToSwapContract_FailsWithExpiredSignature() public {
        uint256 contributionAmount = GOAL;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        // Fast-forward past the campaign end time
        vm.warp(aon.endTime() + 1 days);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 claimAmount = address(aon).balance;
        address swapContract = address(0x456);
        bytes32 preimageHash = bytes32(0);
        address claimAddress = address(0x456);
        address refundAddress = address(0x789);
        uint256 timelock = 7200;
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", preimageHash, claimAddress, refundAddress, timelock
        );

        bytes memory signature = _createClaimSignature(swapContract, claimAmount, deadline, processingFee, lockCallData);

        // Fast-forward past the deadline
        vm.warp(deadline + 1);

        vm.expectRevert(Aon.SignatureExpired.selector);
        aon.claimToSwapContract(ISwapHTLC(swapContract), processingFee, lockCallData, signature, deadline);
    }

    function test_ClaimToSwapContract_FailsWithInvalidSwapContract() public {
        uint256 contributionAmount = GOAL;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        vm.warp(aon.endTime() + 1 days);

        address swapContract = address(0);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 preimageHash = bytes32(0);
        address claimAddress = address(0x456);
        address refundAddress = address(0x789);
        uint256 timelock = 7200;
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", preimageHash, claimAddress, refundAddress, timelock
        );
        bytes memory signature = new bytes(65);

        vm.expectRevert(Aon.InvalidSwapContract.selector);
        aon.claimToSwapContract(ISwapHTLC(swapContract), processingFee, lockCallData, signature, deadline);
    }

    function test_ClaimToSwapContract_VerifiesParameterOrder() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);

        MockSwapHTLC mockSwap = new MockSwapHTLC();
        bytes32 preimageHash = bytes32(uint256(0x1234));
        address claimAddress = address(0x456);
        address refundAddress = address(0x789);
        uint256 timelock = 7200;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 processingFee = 0;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", preimageHash, claimAddress, refundAddress, timelock
        );

        bytes memory signature =
            _createClaimSignature(address(mockSwap), aon.claimableBalance(), deadline, processingFee, lockCallData);

        aon.claimToSwapContract(ISwapHTLC(address(mockSwap)), processingFee, lockCallData, signature, deadline);

        assertEq(mockSwap.lastPreimageHash(), preimageHash, "Preimage hash should match");
        assertEq(mockSwap.lastClaimAddress(), claimAddress, "Claim address should match");
        assertEq(mockSwap.lastRefundAddress(), refundAddress, "Refund address should match");
        assertEq(mockSwap.lastTimelock(), 7200, "Timelock should match");
    }

    function _createClaimSignature(
        address swapContract,
        uint256 amount,
        uint256 deadline,
        uint256 processingFee,
        bytes memory lockCallData
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 lockCallDataHash)"
                ),
                creator,
                swapContract,
                amount,
                aon.nonces(creator),
                deadline,
                processingFee,
                keccak256(lockCallData)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", aon.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /*
    * PROCESSING FEE TESTS
    */

    function test_Claim_SucceedsWhenProcessingFeeIsWithinSafeRange() public {
        // Set up campaign and reach goal with a large creator fee
        uint128 safeCreatorFee = type(uint128).max / 2;
        uint256 largeValue = uint256(type(uint128).max) - 0.5 ether; // Large value that fits in uint128

        // Give contributor1 enough ETH
        vm.deal(contributor1, largeValue);

        // Make a contribution with a large creator fee
        vm.prank(contributor1);
        aon.contribute{value: largeValue}(safeCreatorFee, 0);

        vm.warp(aon.endTime() + 1 days);

        // Claim with a processing fee that's within safe range
        uint256 safeProcessingFee = 1 ether;

        vm.prank(creator);
        aon.claim(safeProcessingFee);

        assertEq(aon.totalCreatorFee(), safeCreatorFee + safeProcessingFee, "Total creator fee should accumulate");
    }

    function test_ClaimToSwapContract_SucceedsWhenProcessingFeeIsWithinSafeRange() public {
        // Set up campaign and reach goal with a large creator fee
        // Use smaller but still large values to avoid VM issues
        uint128 safeCreatorFee = 1000 ether;
        uint256 largeValue = 2000 ether; // msg.value must be > safeCreatorFee

        // Give contributor1 enough ETH
        vm.deal(contributor1, largeValue);

        // Make a contribution with a large creator fee
        vm.prank(contributor1);
        aon.contribute{value: largeValue}(safeCreatorFee, 0);

        vm.warp(aon.endTime() + 1 days);

        // Prepare claim to swap contract
        address swapContract = address(0x456);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 safeProcessingFee = 1 ether;

        // claimableAmount is calculated AFTER processingFee is added to totalCreatorFee
        // So we need to calculate: address(this).balance - (totalCreatorFee + processingFee) - totalContributorFee
        uint256 claimAmount =
            address(aon).balance - (aon.totalCreatorFee() + safeProcessingFee) - aon.totalContributorFee();

        bytes32 preimageHash = bytes32(0);
        address claimAddress = address(0x456);
        address refundAddress = address(0x789);
        uint256 timelock = 7200;

        // Encode lockCallData
        bytes memory lockCallData = abi.encodeWithSignature(
            "lock(bytes32,address,address,uint256)", preimageHash, claimAddress, refundAddress, timelock
        );

        bytes memory signature =
            _createClaimSignature(swapContract, claimAmount, deadline, safeProcessingFee, lockCallData);

        aon.claimToSwapContract(ISwapHTLC(swapContract), safeProcessingFee, lockCallData, signature, deadline);

        assertEq(aon.totalCreatorFee(), safeCreatorFee + safeProcessingFee, "Total creator fee should accumulate");
    }
}

