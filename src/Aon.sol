// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "./AonGoalReachedNative.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import "openzeppelin-contracts/contracts/utils/Nonces.sol";

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

contract Aon is Initializable, Nonces {
    /*
    * EVENTS
    */
    // Contract events
    event Claimed(uint256 amount);
    event Cancelled();
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
    error OnlyCreatorOrFactoryOwnerCanCancel();

    // Claim Errors
    error CannotClaimCancelledContract();
    error CannotClaimFailedContract();
    error CannotClaimUnclaimedContract();
    error OnlyCreatorCanClaim();
    error FailedToSendFundsInClaim(bytes reason);

    // Refund Errors
    error CannotRefundNonActiveContract();
    error CannotRefundClaimedContract();
    error CannotRefundRefundedContract();
    error CannotRefundZeroContribution();
    error InsufficientBalanceForRefund(uint256 balance, uint256 refundAmount, uint256 goal);
    error FailedToRefund(bytes reason);

    // EIP-712 / signature errors
    error InvalidSignature();
    error SignatureExpired();

    // Swipe Funds Errors
    error CannotSwipeFundsInClaimedContract();
    error CannotSwipeFundsInRefundedContract();
    error CannotSwipeFundsBeforeEndOfClaimOrRefundWindow();
    error NoFundsToSwipe();
    error OnlyFactoryCanSwipeFunds();

    // Constants
    uint256 public constant CLAIM_REFUND_WINDOW_IN_SECONDS = 30 days;

    // ---------------------------------------------------------------------
    // EIP-712 CONSTANTS & STATE
    // ---------------------------------------------------------------------

    // solhint-disable-next-line max-line-length
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _REFUND_TYPEHASH =
        keccak256("Refund(address contributor,uint256 amount,uint256 nonce,uint256 deadline)");

    // Cached domain separator built in `initialize`
    bytes32 private _DOMAIN_SEPARATOR;

    /*
    * STATE VARIABLES
    */
    IOwnable public factory;
    address payable public creator;
    uint256 public goal;
    uint256 public endTime;
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
        endTime = block.timestamp + _durationInSeconds;
        goalReachedStrategy = IAonGoalReached(_goalReachedStrategy);

        factory = IOwnable(msg.sender);

        // -----------------------------------------------------------------
        // Build and cache the EIP-712 domain separator for this contract
        // -----------------------------------------------------------------
        _DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("Aon")), // Name
                keccak256(bytes("1")), // Version
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Returns the EIP-712 domain separator used by this contract.
    function domainSeparator() external view returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }

    /*
    * UTILITY FUNCTIONS
    */
    function isFinalized() internal view returns (bool) {
        return (address(this).balance == 0 && block.timestamp > (endTime + CLAIM_REFUND_WINDOW_IN_SECONDS * 2));
    }

    function canRefund(uint256 refundAmount) internal view {
        if (refundAmount == 0) revert CannotRefundZeroContribution();

        // Refund is allowed if:
        // 1. The contract was cancelled.
        // 2. The campaign ended and failed to meet its goal.
        // 3. The campaign was successful, but the creator failed to claim in time.
        // TODO: add a test for the isGoalReached() case
        if (isCancelled || isFailed() || isUnclaimed() || !goalReachedStrategy.isGoalReached()) {
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
        if (!isCreator()) revert OnlyCreatorCanClaim();
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

        if (!isFactoryCall && !isCreatorCall) revert OnlyCreatorOrFactoryOwnerCanCancel();

        return true;
    }

    function canContribute() internal view returns (bool) {
        if (block.timestamp > endTime) revert CannotContributeAfterEndTime();
        if (isCancelled) revert CannotContributeToCancelledContract();
        if (isFinalized()) revert CannotContributeToFinalizedContract();
        if (msg.value == 0) revert InvalidContribution();
        /*
         TODO: should we disallow contributions after the creator has claimed the funds if they claim early?
         How do we derive the isClaimed state? 
         Can we find out if the creator has claimed the funds through outgoing txs?
        */

        return true;
    }

    function canSwipeFunds() internal view returns (bool) {
        if (msg.sender != factory.owner()) revert OnlyFactoryCanSwipeFunds();

        /*
            We take the claim/refund twice as the max delay, in case the funds were not claimed by the creator 
            (claim window) and then some funds were not refunded (refund window).
        */
        if (block.timestamp <= endTime + CLAIM_REFUND_WINDOW_IN_SECONDS * 2) {
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
            block.timestamp > endTime + CLAIM_REFUND_WINDOW_IN_SECONDS && goalReachedStrategy.isGoalReached()
                && address(this).balance > 0
        );
    }

    function isFailed() public view returns (bool) {
        return (block.timestamp > endTime && !goalReachedStrategy.isGoalReached());
    }

    function isSuccessful() public view returns (bool) {
        return (!isCancelled && block.timestamp > endTime && goalReachedStrategy.isGoalReached());
    }

    function isCreator() internal view returns (bool) {
        return msg.sender == creator;
    }

    /*
    * EXTERNAL FUNCTIONS
    */
    function contribute() external payable {
        canContribute();

        // TODO: change the ,msg sender to some reference of the contributor address (passed in the call data?)
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
    }

    /**
     * @notice Refund contributions on behalf of a contributor using an EIP-712
     *         signed message.
     *
     * @param contributor The address that originally contributed and signed
     *                    the permit.
     * @param deadline    Timestamp after which the signature is no longer
     *                    valid.
     * @param v           ECDSA recovery byte.
     * @param r           ECDSA R value.
     * @param s           ECDSA S value.
     */
    function refundWithSignature(address contributor, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        if (block.timestamp > deadline) {
            revert SignatureExpired();
        }

        uint256 refundAmount = contributions[contributor];
        canRefund(refundAmount);

        // -----------------------------------------------------------------
        // Verify EIP-712 signature
        // -----------------------------------------------------------------
        uint256 nonce = nonces(contributor);
        bytes32 structHash = keccak256(abi.encode(_REFUND_TYPEHASH, contributor, refundAmount, nonce, deadline));

        bytes32 digest = MessageHashUtils.toTypedDataHash(_DOMAIN_SEPARATOR, structHash);
        address signer = ECDSA.recover(digest, v, r, s);

        if (signer != contributor) {
            revert InvalidSignature();
        }

        // Consume nonce to prevent replay
        _useNonce(contributor);

        // -----------------------------------------------------------------
        // Execute refund
        // -----------------------------------------------------------------
        contributions[contributor] = 0;

        (bool success, bytes memory reason) = contributor.call{value: refundAmount}("");
        if (!success) {
            revert FailedToRefund(reason);
        }

        emit ContributionRefunded(contributor, refundAmount);
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
