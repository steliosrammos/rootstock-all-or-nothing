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
        uint256 creatorFeeAmount = 0.5 ether;
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
        // Contribute exactly the goal amount with creator fees equal to the contribution
        // This creates a scenario where claimableBalance might be 0
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

        bytes32 preimageHash = bytes32(0);
        uint256 processingFee = 0;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 preimageHash,address refundAddress)"
                ),
                creator,
                swapContract,
                claimAmount,
                aon.nonces(creator),
                deadline,
                processingFee,
                preimageHash,
                address(0x789)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", aon.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 initialNonce = aon.nonces(creator);
        uint256 initialSwapBalance = swapContract.balance;

        vm.expectEmit(true, true, true, true);
        emit Claimed(claimAmount, aon.totalCreatorFee(), aon.totalContributorFee());
        aon.claimToSwapContract(
            ISwapHTLC(swapContract),
            deadline,
            signature,
            0,
            Aon.SwapContractLockParams({
                preimageHash: bytes32(0),
                claimAddress: address(0x456),
                refundAddress: address(0x789),
                timelock: 7200,
                functionSignature: "lock(bytes32,address,address,uint256)"
            })
        );

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
        uint256 nonce = aon.nonces(creator);
        uint256 claimAmount = address(aon).balance;
        address swapContract = address(0x456);
        bytes32 preimageHash = bytes32(0);
        uint256 processingFee = 0;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 preimageHash)"
                ),
                creator,
                swapContract,
                claimAmount,
                nonce,
                deadline,
                processingFee,
                preimageHash
            )
        );

        bytes32 domainSeparator = aon.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign with wrong private key (contributor1's key instead of creator's)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(contributor1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Aon.InvalidSignature.selector);
        aon.claimToSwapContract(
            ISwapHTLC(swapContract),
            deadline,
            signature,
            0,
            Aon.SwapContractLockParams({
                preimageHash: bytes32(0),
                claimAddress: address(0x456),
                refundAddress: address(0x789),
                timelock: 7200,
                functionSignature: "lock(bytes32,address,address,uint256)"
            })
        );
    }

    function test_ClaimToSwapContract_FailsWithExpiredSignature() public {
        uint256 contributionAmount = GOAL;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        // Fast-forward past the campaign end time
        vm.warp(aon.endTime() + 1 days);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = aon.nonces(creator);
        uint256 claimAmount = address(aon).balance;
        address swapContract = address(0x456);
        bytes32 preimageHash = bytes32(0);
        uint256 processingFee = 0;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 preimageHash)"
                ),
                creator,
                swapContract,
                claimAmount,
                nonce,
                deadline,
                processingFee,
                preimageHash
            )
        );

        bytes32 domainSeparator = aon.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Fast-forward past the deadline
        vm.warp(deadline + 1);

        vm.expectRevert(Aon.SignatureExpired.selector);
        aon.claimToSwapContract(
            ISwapHTLC(swapContract),
            deadline,
            signature,
            0,
            Aon.SwapContractLockParams({
                preimageHash: bytes32(0),
                claimAddress: address(0x456),
                refundAddress: address(0x789),
                timelock: 7200,
                functionSignature: "lock(bytes32,address,address,uint256)"
            })
        );
    }

    function test_ClaimToSwapContract_FailsWithInvalidSwapContract() public {
        uint256 contributionAmount = GOAL;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        vm.warp(aon.endTime() + 1 days);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = new bytes(65);

        vm.expectRevert(Aon.InvalidSwapContract.selector);
        aon.claimToSwapContract(
            ISwapHTLC(address(0)),
            deadline,
            signature,
            0,
            Aon.SwapContractLockParams({
                preimageHash: bytes32(0),
                claimAddress: address(0x456),
                refundAddress: address(0x789),
                timelock: 7200,
                functionSignature: "lock(bytes32,address,address,uint256)"
            })
        );
    }

    function test_ClaimToSwapContract_FailsWithInvalidClaimAddress() public {
        uint256 contributionAmount = GOAL;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        vm.warp(aon.endTime() + 1 days);

        address swapContract = address(0x456);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = new bytes(65);

        vm.expectRevert(Aon.InvalidClaimAddress.selector);
        aon.claimToSwapContract(
            ISwapHTLC(swapContract),
            deadline,
            signature,
            0,
            Aon.SwapContractLockParams({
                preimageHash: bytes32(0),
                claimAddress: address(0),
                refundAddress: address(0x789),
                timelock: 7200,
                functionSignature: "lock(bytes32,address,address,uint256)"
            })
        );
    }

    function test_ClaimToSwapContract_FailsWithInvalidRefundAddress() public {
        uint256 contributionAmount = GOAL;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        vm.warp(aon.endTime() + 1 days);

        address swapContract = address(0x456);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = new bytes(65);

        vm.expectRevert(Aon.InvalidRefundAddress.selector);
        aon.claimToSwapContract(
            ISwapHTLC(swapContract),
            deadline,
            signature,
            0,
            Aon.SwapContractLockParams({
                preimageHash: bytes32(0),
                claimAddress: address(0x456),
                refundAddress: address(0),
                timelock: 7200,
                functionSignature: "lock(bytes32,address,address,uint256)"
            })
        );
    }

    function test_ClaimToSwapContract_VerifiesParameterOrder() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);

        MockSwapHTLC mockSwap = new MockSwapHTLC();
        bytes32 preimageHash = bytes32(uint256(0x1234));
        address claimAddress = address(0x456);
        address refundAddress = address(0x789);

        bytes memory signature = _createClaimSignature(
            address(mockSwap), aon.claimableBalance(), block.timestamp + 1 hours, preimageHash, refundAddress
        );

        aon.claimToSwapContract(
            ISwapHTLC(address(mockSwap)),
            block.timestamp + 1 hours,
            signature,
            0,
            Aon.SwapContractLockParams({
                preimageHash: preimageHash,
                claimAddress: claimAddress,
                refundAddress: refundAddress,
                timelock: 7200,
                functionSignature: "lock(bytes32,address,address,uint256)"
            })
        );

        assertEq(mockSwap.lastPreimageHash(), preimageHash, "Preimage hash should match");
        assertEq(mockSwap.lastClaimAddress(), claimAddress, "Claim address should match");
        assertEq(mockSwap.lastRefundAddress(), refundAddress, "Refund address should match");
        assertEq(mockSwap.lastTimelock(), 7200, "Timelock should match");
    }

    function _createClaimSignature(
        address swapContract,
        uint256 amount,
        uint256 deadline,
        bytes32 preimageHash,
        address refundAddress
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 preimageHash,address refundAddress)"
                ),
                creator,
                swapContract,
                amount,
                aon.nonces(creator),
                deadline,
                0,
                preimageHash,
                refundAddress
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", aon.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}

