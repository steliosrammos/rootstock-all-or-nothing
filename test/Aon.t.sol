// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Aon.sol";
import "../src/AonProxy.sol";
import "../src/AonGoalReachedNative.sol";

contract AonTest is Test {
    Aon aon;
    AonGoalReachedNative private goalReachedStrategy;

    address payable private creator = payable(makeAddr("creator"));
    address payable private contributor1 = payable(makeAddr("contributor1"));
    address payable private contributor2 = payable(makeAddr("contributor2"));
    address private factoryOwner;
    address private randomAddress = makeAddr("random");

    uint256 private constant GOAL = 10 ether;
    uint256 private constant DURATION = 30 days;

    event ContributionReceived(address indexed contributor, uint256 amount);
    event ContributionRefunded(address indexed contributor, uint256 amount);
    event Claimed(uint256 amount);
    event Cancelled();
    event Refunded();
    event FundsSwiped();

    /*
    * SETUP
    */

    function setUp() public {
        factoryOwner = address(this);
        goalReachedStrategy = new AonGoalReachedNative();

        // Deploy implementation and proxy
        Aon implementation = new Aon();
        AonProxy proxy = new AonProxy(address(implementation));
        aon = Aon(address(proxy));

        // Initialize contract via proxy
        vm.prank(factoryOwner);
        aon.initialize(creator, GOAL, DURATION, address(goalReachedStrategy));

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
        assertEq(aon.durationInSeconds(), DURATION, "Duration should be set");
        assertEq(address(aon.factory()), factoryOwner, "Factory owner should be this contract");
        assertEq(
            address(aon.goalReachedStrategy()), address(goalReachedStrategy), "Goal reached strategy should be set"
        );
        assertGt(aon.startTime(), 0, "Start time should be set");
        assertEq(aon.isCancelled(), false, "Should not be cancelled initially");
    }

    /*
    * CONTRIBUTE TESTS
    */

    function test_Contribute_Success() public {
        uint256 contributionAmount = 1 ether;
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit ContributionReceived(contributor1, contributionAmount);
        aon.contribute{value: contributionAmount}();

        assertEq(address(aon).balance, contributionAmount, "Contract balance should increase");
        assertEq(aon.contributions(contributor1), contributionAmount, "Contributor's balance should be recorded");
    }

    function test_Contribute_FailsIfZeroAmount() public {
        vm.prank(contributor1);
        vm.expectRevert(Aon.InvalidContribution.selector);
        aon.contribute{value: 0}();
    }

    function test_Contribute_FailsIfAfterEndTime() public {
        vm.warp(aon.endTime() + 1 days);
        vm.prank(contributor1);
        vm.expectRevert(Aon.CannotContributeAfterEndTime.selector);
        aon.contribute{value: 1 ether}();
    }

    function test_Contribute_FailsIfCancelled() public {
        vm.prank(creator);
        aon.cancel();

        vm.prank(contributor1);
        vm.expectRevert(Aon.CannotContributeToCancelledContract.selector);
        aon.contribute{value: 1 ether}();
    }

    /*
    * CLAIM TESTS (SUCCESSFUL CAMPAIGN)
    */

    function test_Claim_Success() public {
        // Contributors meet the goal
        vm.prank(contributor1);
        aon.contribute{value: 5 ether}();
        vm.prank(contributor2);
        aon.contribute{value: 5 ether}();

        // Fast-forward past the end time
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.isSuccessful(), "Campaign should be successful");

        // Creator claims the funds
        uint256 contractBalance = address(aon).balance;
        uint256 creatorInitialBalance = creator.balance;

        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit Claimed(contractBalance);
        aon.claim();

        assertEq(address(aon).balance, 0, "Contract balance should be zero after claim");
        assertEq(creator.balance, creatorInitialBalance + contractBalance, "Creator should receive the funds");
    }

    function test_Claim_FailsIfNotCreator() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}();
        vm.warp(aon.endTime() + 1 days);

        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(Aon.Unauthorized.selector, "Only creator can claim"));
        aon.claim();
    }

    function test_Claim_FailsIfGoalNotReached() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL - 1 ether}();
        vm.warp(aon.endTime() - 1 days);

        vm.prank(creator);
        vm.expectRevert(Aon.GoalNotReached.selector);
        aon.claim();
    }

    function test_Claim_FailsIfCampaignFailed() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(); // Goal not reached

        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.isFailed(), "Campaign should have failed");

        vm.prank(creator);
        vm.expectRevert(Aon.CannotClaimFailedContract.selector);
        aon.claim();
    }

    function test_Claim_FailsIfCancelled() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}();
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
        aon.contribute{value: contributionAmount}();

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
        aon.contribute{value: contributionAmount}();

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
        aon.contribute{value: contributionAmount}();

        // Fast-forward past claim window
        vm.warp(aon.endTime() + aon.CLAIM_REFUND_WINDOW_IN_SECONDS() + 1 days);
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
        aon.contribute{value: contributionAmount}(); // Exactly meets goal

        // Another contribution
        vm.prank(contributor2);
        aon.contribute{value: 1 ether}();

        // Contributor 1 cannot refund because it would bring balance below goal
        vm.prank(contributor1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Aon.InsufficientBalanceForRefund.selector, address(aon).balance, contributionAmount, GOAL
            )
        );
        aon.refund();
    }

    /*
    * REENTRANCY TESTS
    */

    function test_Refund_ReentrancyGuard() public {
        // Setup attacker contract
        MaliciousRefund attacker = new MaliciousRefund(aon);
        vm.deal(address(attacker), 1 ether);

        // Attacker contributes
        attacker.contribute{value: 1 ether}();
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

    function test_Claim_ReentrancyAttack() public {
        // Deploy attacker contract. This attacker will pose as the creator.
        MaliciousCreator attacker = new MaliciousCreator();

        // We need a new Aon instance for this test to set the malicious creator.
        Aon implementation = new Aon();
        AonProxy proxy = new AonProxy(address(implementation));
        Aon aonForTest = Aon(address(proxy));
        vm.prank(factoryOwner);
        aonForTest.initialize(payable(address(attacker)), GOAL, DURATION, address(goalReachedStrategy));

        // The attacker needs to know about the Aon instance.
        attacker.setAon(aonForTest);

        // Fund campaign to success
        vm.prank(contributor1);
        aonForTest.contribute{value: GOAL}();

        vm.warp(aonForTest.endTime() + 1 days);
        assertTrue(aonForTest.isSuccessful());

        // Attacker starts the claim, which should lead to re-entrancy.
        // In the vulnerable contract, the re-entrant `cancel` call will succeed.
        // This test should fail once a re-entrancy guard is added.
        attacker.claim();

        // Check that the attack succeeded (which is bad)
        assertTrue(aonForTest.isCancelled(), "Attack should have cancelled the contract");
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
        aonForTest.initialize(creator, GOAL, DURATION, address(goalReachedStrategy));

        // 4. Link the attacker contract to the new Aon instance
        attacker.setAon(aonForTest);

        // 5. Fund the campaign and let it run its course until funds are swipe-able
        vm.prank(contributor1);
        aonForTest.contribute{value: 1 ether}();
        vm.warp(aonForTest.endTime() + (aonForTest.CLAIM_REFUND_WINDOW_IN_SECONDS() * 2) + 1 days);

        // 6. Attacker tries to swipe funds, which triggers a re-entrant call.
        // The attack should fail because the contract becomes finalized after funds are sent,
        // preventing the cancel() call in the malicious receive() function.
        bytes memory innerError = abi.encodeWithSelector(Aon.CannotCancelFinalizedContract.selector);
        vm.expectRevert(abi.encodeWithSelector(Aon.FailedToSwipeFunds.selector, innerError));
        vm.prank(address(attacker));
        attacker.swipe();

        // 7. Check that the attack failed (which is good) - contract should not be cancelled
        assertFalse(aonForTest.isCancelled(), "Attack should have failed and contract should not be cancelled");
    }

    /*
    * CANCEL TESTS
    */

    function test_Cancel_SuccessByCreator() public {
        vm.prank(creator);
        vm.expectEmit(false, false, false, false);
        emit Cancelled();
        aon.cancel();
        assertTrue(aon.isCancelled(), "Contract should be cancelled");
    }

    function test_Cancel_SuccessByFactoryOwner() public {
        vm.prank(factoryOwner);
        vm.expectEmit(false, false, false, false);
        emit Cancelled();
        aon.cancel();
        assertTrue(aon.isCancelled(), "Contract should be cancelled");
    }

    function test_Cancel_FailsIfUnauthorized() public {
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(Aon.Unauthorized.selector, "Only factory or creator can cancel"));
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
        aon.contribute{value: 1 ether}();

        // Fast-forward past all windows
        vm.warp(aon.endTime() + (aon.CLAIM_REFUND_WINDOW_IN_SECONDS() * 2) + 1 days);

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
        vm.expectRevert(abi.encodeWithSelector(Aon.Unauthorized.selector, "Only factory can swipe funds"));
        aon.swipeFunds();
    }

    function test_SwipeFunds_FailsIfWindowNotOver() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}();
        vm.warp(aon.endTime());

        vm.prank(factoryOwner);
        vm.expectRevert(Aon.CannotSwipeFundsBeforeEndOfClaimOrRefundWindow.selector);
        aon.swipeFunds();
    }

    function test_SwipeFunds_FailsIfNoFunds() public {
        // Fast-forward past all windows
        vm.warp(aon.endTime() + (aon.CLAIM_REFUND_WINDOW_IN_SECONDS() * 2) + 1 days);

        vm.prank(factoryOwner);
        vm.expectRevert(Aon.NoFundsToSwipe.selector);
        aon.swipeFunds();
    }
}

/// @dev A helper contract to test re-entrancy protection on the refund function.
contract MaliciousRefund {
    Aon public immutable aon;

    constructor(Aon _aon) {
        aon = _aon;
    }

    function contribute() external payable {
        aon.contribute{value: msg.value}();
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

/// @dev An attacker contract to test re-entrancy on claim.
/// It tries to cancel the campaign during the claim payout.
contract MaliciousCreator {
    Aon aon;

    function setAon(Aon _aon) external {
        aon = _aon;
    }

    function claim() external {
        aon.claim();
    }

    receive() external payable {
        // When we receive the claimed funds, try to cancel the campaign.
        // This shouldn't be possible in a secure contract.
        if (address(aon).balance == 0) {
            aon.cancel();
        }
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
