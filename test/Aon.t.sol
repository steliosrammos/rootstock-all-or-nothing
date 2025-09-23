// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Aon.sol";
import "../src/AonProxy.sol";
import "../src/AonGoalReachedNative.sol";

contract AonTest is Test {
    Aon aon;
    AonGoalReachedNative private goalReachedStrategy;

    address payable private creator;
    uint256 private creatorPrivateKey;

    address payable private contributor1;
    uint256 private contributor1PrivateKey;

    address payable private contributor2 = payable(makeAddr("contributor2"));
    address private factoryOwner;
    address private randomAddress = makeAddr("random");

    uint256 private constant GOAL = 10 ether;
    uint256 private constant DURATION = 30 days;
    uint256 private constant PLATFORM_FEE = 250; // 2.5% in basis points

    event ContributionReceived(address indexed contributor, uint256 amount);
    event ContributionRefunded(address indexed contributor, uint256 amount);
    event Claimed(uint256 creatorAmount, uint256 totalFee);
    event Cancelled();
    event Refunded();
    event FundsSwiped();

    /*
    * SETUP
    */

    function setUp() public {
        (address _creator, uint256 _creatorPrivateKey) = makeAddrAndKey("creator");
        creator = payable(_creator);
        creatorPrivateKey = _creatorPrivateKey;

        (address _contributor1, uint256 _contributor1PrivateKey) = makeAddrAndKey("contributor1");
        contributor1 = payable(_contributor1);
        contributor1PrivateKey = _contributor1PrivateKey;

        factoryOwner = address(this);
        goalReachedStrategy = new AonGoalReachedNative();

        // Deploy implementation and proxy
        Aon implementation = new Aon();
        AonProxy proxy = new AonProxy(address(implementation));
        aon = Aon(address(proxy));

        // Initialize contract via proxy
        vm.prank(factoryOwner);
        aon.initialize(creator, GOAL, block.timestamp + DURATION, address(goalReachedStrategy), 30 days);

        vm.deal(contributor1, 100 ether);
        vm.deal(contributor2, 100 ether);
        vm.deal(creator, 1 ether); // Give creator some ETH for gas
    }

    /// @dev The test contract itself acts as the factory, so it must implement owner().
    function owner() public view returns (address) {
        return address(this);
    }

    /// @dev The test contract needs to be able to receive swiped funds.
    receive() external payable {}

    /*
    * CONSTRUCTOR TESTS
    */

    function test_Constructor_SetsInitialValues() public view {
        assertEq(aon.creator(), creator, "Creator should be set");
        assertEq(aon.goal(), GOAL, "Goal should be set");
        assertEq(address(aon.factory()), factoryOwner, "Factory owner should be this contract");
        assertEq(
            address(aon.goalReachedStrategy()), address(goalReachedStrategy), "Goal reached strategy should be set"
        );
        assertTrue(aon.endTime() > block.timestamp, "End time should be in the future");
        assertEq(uint256(aon.status()), uint256(Aon.Status.Active), "Should be active initially");
    }

    /*
    * CONTRIBUTE TESTS
    */

    function test_Contribute_Success() public {
        uint256 contributionAmount = 1 ether;
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit ContributionReceived(contributor1, contributionAmount);
        aon.contribute{value: contributionAmount}(0, 0);

        assertEq(address(aon).balance, contributionAmount, "Contract balance should increase");
        assertEq(aon.contributions(contributor1), contributionAmount, "Contributor's balance should be recorded");
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
    * TIP TESTS
    */

    function test_Contribute_WithTip_Success() public {
        uint256 contributionAmount = 1 ether;
        uint256 tipAmount = 0.1 ether;
        uint256 expectedContribution = contributionAmount - tipAmount;

        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit ContributionReceived(contributor1, expectedContribution);
        aon.contribute{value: contributionAmount}(0, tipAmount);

        assertEq(address(aon).balance, contributionAmount, "Contract balance should include tip");
        assertEq(aon.contributions(contributor1), expectedContribution, "Contribution should exclude tip");
        assertEq(aon.totalTip(), tipAmount, "Total tip should be tracked");
    }

    function test_Contribute_WithTip_FailsIfTipExceedsContribution() public {
        uint256 contributionAmount = 1 ether;
        uint256 tipAmount = 1.1 ether; // Tip exceeds contribution

        vm.prank(contributor1);
        vm.expectRevert(Aon.TipCannotExceedContributionAmount.selector);
        aon.contribute{value: contributionAmount}(0, tipAmount);
    }

    function test_Contribute_WithTip_FailsIfTipEqualsContribution() public {
        uint256 contributionAmount = 1 ether;
        uint256 tipAmount = 1 ether; // Tip equals contribution (should fail)

        vm.prank(contributor1);
        vm.expectRevert(Aon.TipCannotExceedContributionAmount.selector);
        aon.contribute{value: contributionAmount}(0, tipAmount);
    }

    function test_Contribute_MultipleTips_AccumulateCorrectly() public {
        uint256 contributionAmount1 = 1 ether;
        uint256 tipAmount1 = 0.1 ether;
        uint256 contributionAmount2 = 2 ether;
        uint256 tipAmount2 = 0.2 ether;

        // First contribution with tip
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount1}(0, tipAmount1);

        // Second contribution with tip
        vm.prank(contributor2);
        aon.contribute{value: contributionAmount2}(0, tipAmount2);

        assertEq(aon.totalTip(), tipAmount1 + tipAmount2, "Total tips should accumulate");
        assertEq(
            aon.contributions(contributor1), contributionAmount1 - tipAmount1, "First contribution should exclude tip"
        );
        assertEq(
            aon.contributions(contributor2), contributionAmount2 - tipAmount2, "Second contribution should exclude tip"
        );
    }

    function test_ContributeFor_WithTips_Success() public {
        uint256 contributionAmount = 1 ether;
        uint256 tipAmount = 0.1 ether;
        uint256 expectedContribution = contributionAmount - tipAmount;

        vm.prank(factoryOwner); // Factory calls contributeFor
        vm.expectEmit(true, true, true, true);
        emit ContributionReceived(contributor1, expectedContribution);
        aon.contributeFor{value: contributionAmount}(contributor1, 0, tipAmount);

        assertEq(address(aon).balance, contributionAmount, "Contract balance should include tip");
        assertEq(aon.contributions(contributor1), expectedContribution, "Contribution should exclude tip");
        assertEq(aon.totalTip(), tipAmount, "Total tip should be tracked");
    }

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
        assertTrue(aon.isSuccessful(), "Campaign should be successful");

        // Creator claims the funds
        uint256 contractBalance = address(aon).balance;
        uint256 totalFee = aon.totalFee();
        uint256 creatorAmount = contractBalance - totalFee;
        uint256 creatorInitialBalance = creator.balance;
        uint256 factoryInitialBalance = factoryOwner.balance;

        vm.prank(creator);
        vm.expectEmit(true, true, false, true);
        emit Claimed(creatorAmount, totalFee);
        aon.claim();

        assertEq(address(aon).balance, 0, "Contract balance should be zero after claim");
        assertEq(creator.balance, creatorInitialBalance + creatorAmount, "Creator should receive the funds");
        assertEq(factoryOwner.balance, factoryInitialBalance + totalFee, "Factory should receive the fee");
    }

    function test_Claim_WithTips_Success() public {
        // Contributors meet the goal with tips
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}(0, 0.5 ether); // 4.5 ether contribution, 0.5 ether tip
        vm.prank(contributor2);
        aon.contribute{value: 5 ether}(0, 0.5 ether); // 4.5 ether contribution, 0.5 ether tip

        // Fast-forward past the end time
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.isSuccessful(), "Campaign should be successful");

        // Creator claims the funds
        uint256 contractBalance = address(aon).balance;
        uint256 totalFee = aon.totalFee();
        uint256 totalTip = aon.totalTip();
        uint256 creatorAmount = contractBalance - totalFee - totalTip;
        uint256 creatorInitialBalance = creator.balance;
        uint256 factoryInitialBalance = factoryOwner.balance;

        vm.prank(creator);
        vm.expectEmit(true, true, false, true);
        emit Claimed(creatorAmount, totalFee);
        aon.claim();

        assertEq(address(aon).balance, 0, "Contract balance should be zero after claim");
        assertEq(
            creator.balance, creatorInitialBalance + creatorAmount, "Creator should receive the funds (excluding tips)"
        );
        assertEq(
            factoryOwner.balance, factoryInitialBalance + totalFee + totalTip, "Factory should receive fees and tips"
        );
    }

    function test_Claim_FailsIfNotCreator() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);

        vm.prank(randomAddress);
        vm.expectRevert(Aon.OnlyCreatorCanClaim.selector);
        aon.claim();
    }

    function test_Claim_FailsIfGoalNotReached() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL - 1 ether}(0, 0);
        vm.warp(aon.endTime() + 1 days);

        vm.prank(creator);
        vm.expectRevert(Aon.CannotClaimFailedContract.selector);
        aon.claim();
    }

    function test_Claim_FailsIfCampaignFailed() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0); // Goal not reached

        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.isFailed(), "Campaign should have failed");

        vm.prank(creator);
        vm.expectRevert(Aon.CannotClaimFailedContract.selector);
        aon.claim();
    }

    function test_Claim_FailsIfCancelled() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.prank(creator);
        aon.cancel();

        vm.prank(creator);
        vm.expectRevert(Aon.CannotClaimCancelledContract.selector);
        aon.claim();
    }

    /*
    * REFUND TESTS
    */

    function test_Refund_SuccessIfCampaignFailed() public {
        uint256 contributionAmount = 1 ether;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        vm.warp(aon.endTime() + 1 days); // Let campaign fail
        assertTrue(aon.isFailed(), "Campaign should have failed");

        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit ContributionRefunded(contributor1, contributionAmount);
        aon.refund();

        assertEq(
            contributor1.balance, contributorInitialBalance + contributionAmount, "Contributor should get money back"
        );
        assertEq(aon.contributions(contributor1), 0, "Contribution record should be cleared");
    }

    function test_Refund_SuccessIfCancelled() public {
        uint256 contributionAmount = 1 ether;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        vm.prank(creator);
        aon.cancel();

        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund();
        assertEq(
            contributor1.balance, contributorInitialBalance + contributionAmount, "Contributor should get money back"
        );
    }

    function test_Refund_SuccessIfUnclaimed() public {
        uint256 contributionAmount = GOAL;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        // Fast-forward past claim window
        vm.warp(aon.endTime() + aon.claimOrRefundWindow() + 1 days);
        assertTrue(aon.isUnclaimed(), "Campaign should be in unclaimed state");

        uint256 contributorInitialBalance = contributor1.balance;
        vm.prank(contributor1);
        aon.refund();
        assertEq(
            contributor1.balance, contributorInitialBalance + contributionAmount, "Contributor should get money back"
        );
    }

    function test_Refund_FailsForZeroContribution() public {
        vm.prank(creator);
        aon.cancel(); // Allow refunds

        vm.prank(contributor1); // Contributor1 has 0 contribution
        vm.expectRevert(Aon.CannotRefundZeroContribution.selector);
        aon.refund();
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
                Aon.InsufficientBalanceForRefund.selector, address(aon).balance, contributionAmount, GOAL
            )
        );
        aon.refund();
    }

    function test_Refund_WithTips_TipsNotRefunded() public {
        uint256 contributionAmount = 1 ether;
        uint256 tipAmount = 0.1 ether;
        uint256 expectedRefund = contributionAmount - tipAmount;

        // Contribute with tip
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, tipAmount);

        // Let campaign fail
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.isFailed(), "Campaign should have failed");

        uint256 contributorInitialBalance = contributor1.balance;
        uint256 factoryInitialBalance = factoryOwner.balance;

        // Refund should only return contribution amount, not tip
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit ContributionRefunded(contributor1, expectedRefund);
        aon.refund();

        assertEq(
            contributor1.balance,
            contributorInitialBalance + expectedRefund,
            "Contributor should get contribution back (not tip)"
        );
        assertEq(factoryOwner.balance, factoryInitialBalance, "Factory should not receive tips on refund");
        assertEq(aon.contributions(contributor1), 0, "Contribution record should be cleared");
        assertEq(aon.totalTip(), tipAmount, "Total tip should remain unchanged");
    }

    function test_Refund_WithTips_AfterCancellation_TipsNotRefunded() public {
        uint256 contributionAmount = 1 ether;
        uint256 tipAmount = 0.1 ether;
        uint256 expectedRefund = contributionAmount - tipAmount;

        // Contribute with tip
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, tipAmount);

        // Cancel campaign
        vm.prank(creator);
        aon.cancel();

        uint256 contributorInitialBalance = contributor1.balance;
        uint256 factoryInitialBalance = factoryOwner.balance;

        // Refund should only return contribution amount, not tip
        vm.prank(contributor1);
        aon.refund();

        assertEq(
            contributor1.balance,
            contributorInitialBalance + expectedRefund,
            "Contributor should get contribution back (not tip)"
        );
        assertEq(factoryOwner.balance, factoryInitialBalance, "Factory should not receive tips on refund");
        assertEq(aon.totalTip(), tipAmount, "Total tip should remain unchanged");
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
        assertEq(aon.contributions(address(attacker)), 1 ether);

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
        aonForTest.initialize(creator, GOAL, DURATION, address(goalReachedStrategy), 30 days);

        // 4. Link the attacker contract to the new Aon instance
        attacker.setAon(aonForTest);

        // 5. Fund the campaign and let it run its course until funds are swipe-able
        vm.prank(contributor1);
        aonForTest.contribute{value: 1 ether}(0, 0);
        vm.warp(aonForTest.endTime() + (aonForTest.claimOrRefundWindow() * 2) + 1 days);

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

    /*
    * CANCEL TESTS
    */

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

    /*
    * SWIPE FUNDS TESTS
    */

    function test_SwipeFunds_Success() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past all windows
        vm.warp(aon.endTime() + (aon.claimOrRefundWindow() * 2) + 1 days);

        uint256 contractBalance = address(aon).balance;
        uint256 factoryInitialBalance = factoryOwner.balance;

        vm.prank(factoryOwner);
        vm.expectEmit(true, false, false, true);
        emit FundsSwiped();
        aon.swipeFunds();

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(factoryOwner.balance, factoryInitialBalance + contractBalance, "Factory owner should receive funds");
    }

    function test_SwipeFunds_FailsIfNotFactoryOwner() public {
        vm.prank(randomAddress);
        vm.expectRevert(Aon.OnlyFactoryCanSwipeFunds.selector);
        aon.swipeFunds();
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
        vm.warp(aon.endTime() + (aon.claimOrRefundWindow() * 2) + 1 days);

        vm.prank(factoryOwner);
        vm.expectRevert(Aon.NoFundsToSwipe.selector);
        aon.swipeFunds();
    }

    function test_RefundToSwapContract_Success() public {
        uint256 contributionAmount = 1 ether;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        // Cancel campaign to allow refunds
        vm.prank(creator);
        aon.cancel();

        // Create signature for refund
        address swapContract = address(0x123);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = aon.nonces(contributor1);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Refund(address contributor,address swapContract,uint256 amount,uint256 nonce,uint256 deadline)"
                ),
                contributor1,
                swapContract,
                contributionAmount,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = aon.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign the digest with contributor1's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(contributor1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 swapContractInitialBalance = swapContract.balance;

        // Execute refund with signature
        vm.expectEmit(true, true, true, true);
        emit ContributionRefunded(contributor1, contributionAmount);
        aon.refundToSwapContract(contributor1, swapContract, deadline, signature, bytes32(0), address(0x123), 3600, 0);

        // Verify refund was successful
        assertEq(
            swapContract.balance, swapContractInitialBalance + contributionAmount, "Swap contract should receive refund"
        );
        assertEq(aon.contributions(contributor1), 0, "Contribution should be cleared");
        assertEq(aon.nonces(contributor1), nonce + 1, "Nonce should be incremented");
    }

    function test_RefundToSwapContract_WithProcessingFee_Success() public {
        uint256 contributionAmount = 1 ether;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);
        
        uint256 processingFee = 0.1 ether;
        uint256 expectedRefund = contributionAmount - processingFee;

        // Cancel campaign to allow refunds
        vm.prank(creator);
        aon.cancel();

        // Create signature for refund
        address swapContract = address(0x123);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = aon.nonces(contributor1);

        bytes memory signature = _createRefundSignature(
            contributor1,
            swapContract,
            expectedRefund,
            deadline,
            contributor1PrivateKey
        );

        uint256 initialBalance = swapContract.balance;

        // Execute refund with signature
        vm.expectEmit(true, true, true, true);
        emit ContributionRefunded(contributor1, expectedRefund);
        aon.refundToSwapContract(
            contributor1, 
            swapContract, 
            deadline, 
            signature, 
            bytes32(0), 
            address(0x123), 
            3600, 
            processingFee
        );

        // Verify refund was successful
        assertEq(swapContract.balance, initialBalance + expectedRefund, "Swap contract should receive refund");
        assertEq(aon.contributions(contributor1), 0, "Contribution should be cleared");
        assertEq(aon.nonces(contributor1), nonce + 1, "Nonce should be incremented");
    }

    // Helper function to create refund signature
    function _createRefundSignature(
        address contributor,
        address swapContract,
        uint256 amount,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        uint256 nonce = aon.nonces(contributor);
        
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Refund(address contributor,address swapContract,uint256 amount,uint256 nonce,uint256 deadline)"
                ),
                contributor,
                swapContract,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", aon.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_RefundToSwapContract_FailsWithInvalidSignature() public {
        uint256 contributionAmount = 1 ether;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        vm.prank(creator);
        aon.cancel();

        address swapContract = address(0x123);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = aon.nonces(contributor1);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Refund(address contributor,address swapContract,uint256 amount,uint256 nonce,uint256 deadline)"
                ),
                contributor1,
                swapContract,
                contributionAmount,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = aon.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign with wrong private key (contributor2's key instead of contributor1's)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, digest); // contributor2 uses key index 2
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Aon.InvalidSignature.selector);
        aon.refundToSwapContract(contributor1, swapContract, deadline, signature, bytes32(0), address(0x123), 3600, 0);
    }

    function test_RefundToSwapContract_FailsWithExpiredSignature() public {
        uint256 contributionAmount = 1 ether;
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        vm.prank(creator);
        aon.cancel();

        address swapContract = address(0x123);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = aon.nonces(contributor1);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Refund(address contributor,address swapContract,uint256 amount,uint256 nonce,uint256 deadline)"
                ),
                contributor1,
                swapContract,
                contributionAmount,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = aon.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Fast-forward past the deadline
        vm.warp(deadline + 1);

        vm.expectRevert(Aon.SignatureExpired.selector);
        aon.refundToSwapContract(contributor1, swapContract, deadline, signature, bytes32(0), address(0x123), 3600, 0);
    }

    function test_ClaimToSwapContract_Success() public {
        uint256 contributionAmount = GOAL; // Contribute exactly the goal amount
        vm.prank(contributor1);
        aon.contribute{value: contributionAmount}(0, 0);

        // Fast-forward past the campaign end time
        vm.warp(aon.endTime() + 1 days);

        // Verify goal is reached
        assertTrue(aon.isSuccessful(), "Campaign should be successful");

        // Create signature for claim
        address swapContract = address(0x456);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = aon.nonces(creator);
        uint256 claimAmount = address(aon).balance;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline)"),
                creator,
                swapContract,
                claimAmount,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = aon.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign the digest with creator's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 swapContractInitialBalance = swapContract.balance;

        // Get the actual platform fee from the contract
        uint256 platformFee = aon.totalFee();
        uint256 creatorAmount = claimAmount - platformFee;

        // Execute claim with signature
        vm.expectEmit(true, true, true, true);
        emit Claimed(creatorAmount, platformFee);
        aon.claimToSwapContract(swapContract, deadline, signature, bytes32(0), address(0x456), 7200);

        // Verify claim was successful
        assertEq(
            swapContract.balance,
            swapContractInitialBalance + creatorAmount,
            "Swap contract should receive creator amount"
        );
        assertEq(aon.nonces(creator), nonce + 1, "Nonce should be incremented");
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

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline)"),
                creator,
                swapContract,
                claimAmount,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = aon.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign with wrong private key (contributor1's key instead of creator's)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(contributor1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Aon.InvalidSignature.selector);
        aon.claimToSwapContract(swapContract, deadline, signature, bytes32(0), address(0x456), 7200);
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

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline)"),
                creator,
                swapContract,
                claimAmount,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = aon.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Fast-forward past the deadline
        vm.warp(deadline + 1);

        vm.expectRevert(Aon.SignatureExpired.selector);
        aon.claimToSwapContract(swapContract, deadline, signature, bytes32(0), address(0x456), 7200);
    }
}

/// @dev A helper contract to test re-entrancy protection on the refund function.
contract MaliciousRefund {
    Aon public immutable aon;

    constructor(Aon _aon) {
        aon = _aon;
    }

    function contribute(uint256 fee, uint256 tip) external payable {
        aon.contribute{value: msg.value}(fee, tip);
    }

    function startAttack() external {
        aon.refund();
    }

    // This function is called when the contract receives Ether.
    // It will try to call refund() again, exploiting a potential re-entrancy vulnerability.
    receive() external payable {
        // The re-entrant call should fail if the contract is secure.
        aon.refund();
    }
}

/// @dev A mock factory used for the swipeFunds re-entrancy test.
/// It allows us to set a malicious owner.
contract MaliciousFactory is IOwnable {
    address public immutable override owner;

    constructor(address _owner) {
        owner = _owner;
    }
}

/// @dev An attacker contract to test re-entrancy on swipeFunds.
/// It poses as the factory owner and tries to cancel the campaign
/// when it receives the swiped funds.
contract MaliciousFactoryOwner {
    Aon aon;

    function setAon(Aon _aon) external {
        aon = _aon;
    }

    function swipe() external {
        aon.swipeFunds();
    }

    receive() external payable {
        // When we receive the swiped funds, try to cancel.
        // The `cancel` call will check if `msg.sender == factory.owner()`.
        // Since this contract is the factory owner in the test setup,
        // the vulnerable contract will allow this.
        aon.cancel();
    }
}
