// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "./AonGoalReachedNative.sol";

interface IOwnable {
    function owner() external view returns (address);
}

/*
    CONTRACT STATES

    Contract states are derived or implicit, to avoid storing a state enum.

    - Active: default state. The contract is active and accepting contributions.
    - Cancelled: the creator has cancelled the contract.
    - Refunded / Claimed: final states of the contract. Implicit states, when the balance is 0 and the contract has expired.
    - Successful/Failed: Implicit states, based on the project balance while the project hasn't expired yet.
*/

contract Aon is Initializable {
    /*
    * EVENTS
    */
    // Contract events
    event Claimed(uint256 amount);
    event Cancelled();
    event Refunded();
    event FundsSwiped();

    // Contribution events
    event ContributionRefunded(address indexed contributor, uint256 amount);
    event ContributionReceived(address indexed contributor, uint256 amount);

    error GoalNotReached();
    error GoalReachedAlready();
    error InvalidContribution();
    error FailedToSwipeFunds(bytes reason);

    /*
    * STATE ERRORS
    */
    // Contribute Errors
    error CannotContributeToCancelledContract();
    error CannotContributeToFinalizedContract();
    error CannotContributeAfterEndTime();

    // Cancel Errors
    error CannotCancelCancelledContract();
    error CannotCancelFinalizedContract();

    // Claim Errors
    error CannotClaimCancelledContract();
    error CannotClaimFailedContract();
    error CannotClaimUnclaimedContract();
    error FailedToSendFundsInClaim(bytes reason);

    // Refund Errors
    error CannotRefundNonActiveContract();
    error CannotRefundClaimedContract();
    error CannotRefundRefundedContract();
    error CannotRefundZeroContribution();
    error InsufficientBalanceForRefund(uint256 balance, uint256 refundAmount, uint256 goal);
    error FailedToRefund(bytes reason);

    // Swipe Funds Errors
    error CannotSwipeFundsInClaimedContract();
    error CannotSwipeFundsInRefundedContract();
    error CannotSwipeFundsBeforeEndOfClaimOrRefundWindow();
    error NoFundsToSwipe();

    // Permission Errors
    error Unauthorized(string reason);

    // Constants
    uint256 public constant CLAIM_REFUND_WINDOW_IN_SECONDS = 30 days;

    /*
    * STATE VARIABLES
    */
    IOwnable public factory;
    address payable public creator;
    uint256 public goal;
    uint256 public durationInSeconds;
    uint256 public startTime;
    bool public isCancelled = false;
    mapping(address => uint256) public contributions;
    IAonGoalReached public goalReachedStrategy;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address payable _creator,
        uint256 _goal,
        uint256 _durationInSeconds,
        address _goalReachedStrategy
    ) public initializer {
        creator = _creator;
        goal = _goal;
        durationInSeconds = _durationInSeconds;
        startTime = block.timestamp;
        goalReachedStrategy = IAonGoalReached(_goalReachedStrategy);

        factory = IOwnable(msg.sender);
    }

    /*
    * UTILITY FUNCTIONS
    */
    function endTime() public view returns (uint256) {
        return startTime + durationInSeconds;
    }

    function isFinalized() internal view returns (bool) {
        return (address(this).balance == 0 && block.timestamp > (endTime() + CLAIM_REFUND_WINDOW_IN_SECONDS * 2));
    }

    function canRefund(uint256 refundAmount) internal view {
        if (refundAmount == 0) revert CannotRefundZeroContribution();

        // Refund is allowed if:
        // 1. The contract was cancelled.
        // 2. The campaign ended and failed to meet its goal.
        // 3. The campaign was successful, but the creator failed to claim in time.
        if (isCancelled || isFailed() || isUnclaimed()) {
            return;
        }

        uint256 balance = address(this).balance;

        // Optional: Allow refunds during an active, successful campaign if it doesn't drop the total below the goal.
        if (goalReachedStrategy.isGoalReached() && balance - refundAmount >= goal) return;

        if (goalReachedStrategy.isGoalReached() && balance - refundAmount < goal) {
            revert InsufficientBalanceForRefund(balance, refundAmount, goal);
        }
    }

    function canClaim() internal view returns (bool) {
        if (!isCreator()) revert Unauthorized("Only creator can claim");
        if (isCancelled) revert CannotClaimCancelledContract();
        if (isFailed()) revert CannotClaimFailedContract();
        if (isUnclaimed()) revert CannotClaimUnclaimedContract();
        if (!goalReachedStrategy.isGoalReached()) revert GoalNotReached();

        return true;
    }

    function canCancel() internal view returns (bool) {
        if (isCancelled) revert CannotCancelCancelledContract();
        if (isFinalized()) revert CannotCancelFinalizedContract();

        bool isFactoryCall = msg.sender == factory.owner();
        bool isCreatorCall = isCreator();

        if (!isFactoryCall && !isCreatorCall) revert Unauthorized("Only factory or creator can cancel");

        return true;
    }

    function canContribute() internal view returns (bool) {
        if (block.timestamp > endTime()) revert CannotContributeAfterEndTime();
        if (isCancelled) revert CannotContributeToCancelledContract();
        if (isFinalized()) revert CannotContributeToFinalizedContract();
        if (msg.value == 0) revert InvalidContribution();

        return true;
    }

    function canSwipeFunds() internal view returns (bool) {
        if (msg.sender != factory.owner()) revert Unauthorized("Only factory can swipe funds");

        /*
            We take the claim/refund twice as the max delay, in case the funds were not claimed by the creator 
            (claim window) and then some funds were not refunded (refund window).
        */
        if (block.timestamp <= endTime() + CLAIM_REFUND_WINDOW_IN_SECONDS * 2) {
            revert CannotSwipeFundsBeforeEndOfClaimOrRefundWindow();
        }

        if (address(this).balance == 0) revert NoFundsToSwipe();

        return true;
    }

    /*
    * DERIVED STATE FUNCTIONS
    */
    function isUnclaimed() public view returns (bool) {
        return (
            block.timestamp > endTime() + CLAIM_REFUND_WINDOW_IN_SECONDS && goalReachedStrategy.isGoalReached()
                && address(this).balance > 0
        );
    }

    function isFailed() public view returns (bool) {
        return (block.timestamp > endTime() && !goalReachedStrategy.isGoalReached());
    }

    function isSuccessful() public view returns (bool) {
        return (!isCancelled && block.timestamp > endTime() && goalReachedStrategy.isGoalReached());
    }

    function isCreator() internal view returns (bool) {
        return msg.sender == creator;
    }

    /*
    * EXTERNAL FUNCTIONS
    */
    function contribute() external payable {
        canContribute();

        contributions[msg.sender] += msg.value;
        emit ContributionReceived(msg.sender, msg.value);
    }

    function refund() external {
        uint256 refundAmount = contributions[msg.sender];
        canRefund(refundAmount);

        contributions[msg.sender] = 0;

        // We refund the contributor
        (bool success, bytes memory reason) = msg.sender.call{value: refundAmount}("");
        if (!success) {
            revert FailedToRefund(reason);
        }

        emit ContributionRefunded(msg.sender, refundAmount);

        // If the contract has no funds left, we emit the Refunded event to indicate the contract is fully refunded
        if (address(this).balance == 0) emit Refunded();
    }

    function claim() external {
        canClaim();

        uint256 claimAmount = address(this).balance;
        (bool success, bytes memory reason) = creator.call{value: claimAmount}("");
        require(success, FailedToSendFundsInClaim(reason));

        emit Claimed(claimAmount);
    }

    function cancel() external {
        canCancel();
        isCancelled = true;
        emit Cancelled();
    }

    function swipeFunds() public {
        canSwipeFunds();

        (bool success, bytes memory reason) = factory.owner().call{value: address(this).balance}("");
        require(success, FailedToSwipeFunds(reason));

        emit FundsSwiped();
    }
}
