// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Aon.sol";
import "../src/AonProxy.sol";
import "../src/AonGoalReachedNative.sol";

contract AonGetStatusTest is Test {
    Aon aon;
    AonGoalReachedNative private goalReachedStrategy;

    address payable private creator;
    uint256 private creatorPrivateKey;

    address payable private contributor1;
    uint256 private contributor1PrivateKey;

    address payable private contributor2 = payable(makeAddr("contributor2"));
    address private factoryOwner;
    address payable private feeRecipient = payable(makeAddr("feeRecipient"));

    uint256 private constant GOAL = 10 ether;
    uint32 private constant DURATION = 30 days;

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

    /*
    * GET STATUS TESTS
    */

    function test_GetStatus_ReturnsActive_WhenCampaignIsRunning() public {
        // No contributions yet, before end time
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Active), "Should be Active initially");

        // Some contributions but goal not reached, before end time
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Active), "Should be Active when goal not reached");
    }

    function test_GetStatus_ReturnsSuccessful_WhenGoalReachedWithinClaimWindow() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past end time but still within claim window
        vm.warp(aon.endTime() + 1 days);
        assertTrue(aon.endTime() + aon.claimWindow() > block.timestamp, "Should still be within claim window");

        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Successful), "Should be Successful");
    }

    function test_GetStatus_ReturnsUnclaimed_WhenGoalReachedButClaimWindowPassed() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past claim window
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Unclaimed), "Should be Unclaimed");
    }

    function test_GetStatus_ReturnsUnclaimed_WhenStatusIsSetToUnclaimed() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        // Fast-forward past claim window
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);

        // First refund sets status to Unclaimed
        vm.prank(contributor1);
        aon.refund(0);

        // Verify status is stored as Unclaimed
        assertEq(uint256(aon.status()), uint256(Aon.Status.Unclaimed), "Stored status should be Unclaimed");
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Unclaimed), "getStatus should return Unclaimed");
    }

    function test_GetStatus_ReturnsUnclaimed_AfterBalanceDropsBelowGoal() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.prank(contributor2);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past claim window
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);

        // First refund drops balance below goal
        vm.prank(contributor1);
        aon.refund(0);

        // Status should still be Unclaimed even though balance is below goal
        assertTrue(aon.goalBalance() < GOAL, "Balance should be below goal");
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Unclaimed), "Should remain Unclaimed");
    }

    function test_GetStatus_ReturnsFailed_WhenGoalNotReachedAndTimeExpired() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL - 1 ether}(0, 0); // Goal not reached

        // Fast-forward past end time
        vm.warp(aon.endTime() + 1 days);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Failed), "Should be Failed");
    }

    function test_GetStatus_ReturnsCancelled_WhenContractIsCancelled() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        vm.prank(creator);
        aon.cancel();

        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Cancelled), "Should be Cancelled");
    }

    function test_GetStatus_ReturnsClaimed_WhenFundsAreClaimed() public {
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);

        vm.warp(aon.endTime() + 1 days);

        vm.prank(creator);
        aon.claim(0);

        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Claimed), "Should be Claimed");
    }

    function test_GetStatus_ReturnsFinalized_WhenContractIsEmptyAndWindowsExpired() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past all windows
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        // Swipe funds to empty the contract
        vm.prank(factoryOwner);
        aon.swipeFunds(feeRecipient);

        assertEq(address(aon).balance, 0, "Contract should be empty");
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Finalized), "Should be Finalized");
    }

    function test_GetStatus_ReturnsFinalized_AfterAllRefundsAndWindowsExpired() public {
        vm.prank(contributor1);
        aon.contribute{value: 1 ether}(0, 0);

        // Fast-forward past end time
        vm.warp(aon.endTime() + 1 days);

        // Refund all contributions
        vm.prank(contributor1);
        aon.refund(0);

        // Fast-forward past all windows
        vm.warp(aon.endTime() + aon.claimWindow() + aon.refundWindow() + 1 days);

        assertEq(address(aon).balance, 0, "Contract should be empty");
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Finalized), "Should be Finalized");
    }

    function test_GetStatus_CancelledTakesPriorityOverDerivedStates() public {
        // Test that Cancelled takes priority over derived states like Successful
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days); // Would be Successful
        vm.prank(creator);
        aon.cancel();
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Cancelled), "Cancelled should override Successful");
    }

    function test_GetStatus_ClaimedTakesPriorityOverDerivedStates() public {
        // Test that Claimed takes priority over derived states like Successful
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + 1 days);
        vm.prank(creator);
        aon.claim(0);
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Claimed), "Claimed should override Successful");
    }

    function test_GetStatus_StoredUnclaimedTakesPriority() public {
        // Test that stored Unclaimed status is returned correctly
        vm.prank(contributor1);
        aon.contribute{value: GOAL}(0, 0);
        vm.warp(aon.endTime() + aon.claimWindow() + 1 days);
        vm.prank(contributor1);
        aon.refund(0); // Sets status to Unclaimed
        assertEq(uint256(aon.getStatus()), uint256(Aon.Status.Unclaimed), "Stored Unclaimed should be returned");
    }
}

