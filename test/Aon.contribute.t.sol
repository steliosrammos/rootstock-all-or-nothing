// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Aon.sol";
import "../src/AonProxy.sol";
import "../src/AonGoalReachedNative.sol";

contract AonContributeTest is Test {
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
    uint256 private constant CONTRIBUTION_AMOUNT = 1 ether;
    uint256 private constant PROCESSING_FEE = 0.1 ether;

    event ContributionReceived(address indexed contributor, uint256 amount);

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

