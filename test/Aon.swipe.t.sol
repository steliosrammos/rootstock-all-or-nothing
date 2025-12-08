// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Aon.sol";
import "../src/AonProxy.sol";
import "../src/AonGoalReachedNative.sol";

contract AonRefundTest is Test {
    Aon aon;
    AonGoalReachedNative private goalReachedStrategy;

    address payable private creator;
    uint256 private creatorPrivateKey;

    address payable private contributor1;
    uint256 private contributor1PrivateKey;

    address payable private contributor2 = payable(makeAddr("contributor2"));
    address private factoryOwner;
    address private randomAddress = makeAddr("random");
    address payable private feeRecipient = payable(makeAddr("feeRecipient"));

    uint256 private constant GOAL = 10 ether;
    uint32 private constant DURATION = 30 days;
    uint256 private constant PLATFORM_FEE = 250; // 2.5% in basis points
    uint256 private constant CONTRIBUTION_AMOUNT = 1 ether;
    uint256 private constant PROCESSING_FEE = 0.1 ether;

    event ContributionReceived(address indexed contributor, uint256 amount);
    event ContributionRefunded(address indexed contributor, uint256 amount);
    event Claimed(uint256 creatorAmount, uint256 creatorFeeAmount, uint256 contributorFeeAmount);
    event Cancelled();
    event Refunded();
    event FundsSwiped(address recipient, uint256 feeRecipientAmount, uint256 recipientAmount);

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
        aon.initialize(creator, GOAL, DURATION, address(goalReachedStrategy), 30 days, 30 days, feeRecipient);

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
        aonForTest.initialize(creator, GOAL, DURATION, address(goalReachedStrategy), 30 days, 30 days, feeRecipient);

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
        attacker.swipe(payable(address(attacker)));

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
        uint256 platformAmount = aon.totalContributorFee(); // 0 in this test
        uint256 recipientAmount = contractBalance - platformAmount;

        vm.prank(factoryOwner);
        vm.expectEmit(true, false, false, true);
        emit FundsSwiped(feeRecipient, platformAmount, recipientAmount);
        aon.swipeFunds(feeRecipient);

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance, feeRecipientInitialBalance + contractBalance, "Fee recipient should receive funds"
        );
    }

    function test_SwipeFunds_FailsIfNotFactoryOwner() public {
        vm.prank(randomAddress);
        vm.expectRevert(Aon.OnlyFactoryCanSwipeFunds.selector);
        aon.swipeFunds(feeRecipient);
    }

    function test_SwipeFunds_FailsIfWindowNotOver() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        vm.warp(aon.endTime());

        vm.prank(factoryOwner);
        vm.expectRevert(Aon.CannotSwipeFundsBeforeEndOfClaimOrRefundWindow.selector);
        aon.swipeFunds(feeRecipient);
    }

    function test_SwipeFunds_FailsIfNoFunds() public {
        // Fast-forward past all windows
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        vm.prank(factoryOwner);
        vm.expectRevert(Aon.NoFundsToSwipe.selector);
        aon.swipeFunds(feeRecipient);
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
        uint256 recipientInitialBalance = randomAddress.balance;

        vm.prank(factoryOwner);
        vm.expectEmit(true, false, false, true);
        emit FundsSwiped(randomAddress, platformAmount, recipientAmount);
        aon.swipeFunds(payable(randomAddress));

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + platformAmount,
            "Fee recipient should receive platform fees"
        );
        assertEq(
            randomAddress.balance,
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
        uint256 recipientInitialBalance = randomAddress.balance;

        vm.prank(factoryOwner);
        aon.swipeFunds(payable(randomAddress));

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance + platformAmount,
            "Fee recipient should receive platform fees including contributor fees"
        );
        assertEq(
            randomAddress.balance,
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
        uint256 recipientInitialBalance = randomAddress.balance;

        vm.prank(factoryOwner);
        vm.expectEmit(true, false, false, true);
        emit FundsSwiped(randomAddress, platformAmount, recipientAmount);
        aon.swipeFunds(payable(randomAddress));

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance,
            "Fee recipient should not receive anything for failed contracts"
        );
        assertEq(
            randomAddress.balance,
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
        uint256 recipientInitialBalance = randomAddress.balance;

        vm.prank(factoryOwner);
        aon.swipeFunds(payable(randomAddress));

        assertEq(address(aon).balance, 0, "Contract balance should be zero");
        assertEq(
            feeRecipient.balance,
            feeRecipientInitialBalance,
            "Fee recipient should not receive anything when there are no platform fees"
        );
        assertEq(
            randomAddress.balance,
            recipientInitialBalance + contractBalance,
            "Recipient should receive all funds when there are no platform fees"
        );
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

        function swipe(address payable recipient) external {
            aon.swipeFunds(recipient);
        }

        receive() external payable {
            // When we receive the swiped funds, try to cancel.
            // The `cancel` call will check if `msg.sender == factory.owner()`.
            // Since this contract is the factory owner in the test setup,
            // the vulnerable contract will allow this.
            aon.cancel();
        }
    }
