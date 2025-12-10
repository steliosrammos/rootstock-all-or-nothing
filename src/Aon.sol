// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "./AonGoalReachedNative.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import "openzeppelin-contracts/contracts/utils/Nonces.sol";

interface IOwnable {
    function owner() external view returns (address);
}

interface IFactory is IOwnable {
    function swipeRecipient() external view returns (address payable);
    function feeRecipient() external view returns (address payable);
}

/**
 * @title ISwapHTLC
 * @dev Interface for Boltz HTLC swap contracts
 * @notice This interface defines the standard lock function used by Boltz swap contracts
 *        for cross-chain atomic swaps
 */
interface ISwapHTLC {
    /**
     * @notice Locks funds in the swap contract with the specified parameters
     * @param preimageHash The hash of the preimage that will unlock the funds
     * @param claimAddress The address that can claim the locked funds
     * @param refundAddress The address that can refund the locked funds
     * @param timelock The timelock value in seconds
     * @dev This function should be payable to receive the locked funds
     */
    function lock(bytes32 preimageHash, address claimAddress, address refundAddress, uint256 timelock) external payable;
}

contract Aon is Initializable, Nonces {
    /*
    * EVENTS
    */
    // Contract events
    event Claimed(uint256 creatorAmount, uint256 creatorFeeAmount, uint256 contributorFeeAmount);
    event Cancelled();
    event FundsSwiped(address recipient, uint256 feeRecipientAmount, uint256 recipientAmount);

    // Contribution events
    event ContributionRefunded(address indexed contributor, uint256 amount);
    event ContributionReceived(address indexed contributor, uint256 amount);

    error GoalNotReached();
    error GoalReachedAlready();
    error InvalidContribution();
    error FailedToSwipeFunds(bytes reason);
    error AlreadyClaimed();

    // Initialization validation errors
    error InvalidGoal();
    error InvalidDuration();
    error InvalidClaimWindow();
    error InvalidRefundWindow();
    error InvalidGoalReachedStrategy();
    error InvalidCreator();

    /*
    * STATE ERRORS
    */
    // Contribute Errors
    error ContributorFeeCannotExceedContributionAmount();
    error CannotContributeToCancelledContract();
    error CannotContributeToClaimedContract();
    error CannotContributeToFinalizedContract();
    error CannotContributeAfterEndTime();

    // Cancel Errors
    error CannotCancelCancelledContract();
    error CannotCancelClaimedContract();
    error CannotCancelFinalizedContract();
    error OnlyCreatorOrFactoryOwnerCanCancel();

    // Claim Errors
    error CannotClaimCancelledContract();
    error CannotClaimClaimedContract();
    error CannotClaimFailedContract();
    error CannotClaimAfterClaimWindow();
    error OnlyCreatorCanClaim();
    error FailedToSendFundsInClaim(bytes reason);
    error FailedToSendFeeRecipientAmount(bytes reason);

    // Refund Errors
    error CannotRefundNonActiveContract();
    error CannotRefundClaimedContract();
    error CannotRefundRefundedContract();
    error CannotRefundZeroContribution();
    error InsufficientBalanceForRefund(uint256 balance, uint256 refundAmount, uint256 goal);
    error ProcessingFeeHigherThanRefundAmount(uint256 refundAmount, uint256 processingFee);
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

    // Swap Contract Errors
    error InvalidSwapContract();
    error InvalidClaimAddress();
    error InvalidRefundAddress();

    // Structs
    struct SwapContractLockParams {
        string functionSignature;
        bytes32 preimageHash;
        address claimAddress;
        address refundAddress;
        uint256 timelock;
    }

    // Status enum
    enum Status {
        Active, // 0 - Campaign running, accepting contributions
        Cancelled, // 1 - Campaign cancelled by creator/admin
        Claimed, // 2 - Funds claimed by creator
        Successful, // 3 - Goal reached, within claim window, can be claimed
        Failed, // 4 - Time expired without reaching goal
        Unclaimed, // 5 - Goal reached but creator didn't claim in time
        Finalized // 6 - Contract empty, all windows expired, no actions possible
    }

    // ---------------------------------------------------------------------
    // EIP-712 CONSTANTS & STATE
    // ---------------------------------------------------------------------

    // solhint-disable-next-line max-line-length
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _REFUND_TO_SWAP_CONTRACT_TYPEHASH = keccak256(
        "Refund(address contributor,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 preimageHash,address refundAddress)"
    );
    bytes32 private constant _CLAIM_TO_SWAP_CONTRACT_TYPEHASH = keccak256(
        "Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 preimageHash,address refundAddress)"
    );

    // Cached domain separator built in `initialize`
    bytes32 private _DOMAIN_SEPARATOR;

    /*
    * STATE VARIABLES
    */
    IFactory public factory;
    address payable public creator;
    uint256 public goal;
    uint256 public endTime;
    uint256 public totalCreatorFee;

    uint256 public totalContributorFee;
    uint32 public claimWindow;
    uint32 public refundWindow;
    uint8 public constant VERSION = 1;
    /*
    * The status is only updated to Active, Claimed or Cancelled, other statuses are derived from contract state
    */
    Status public status = Status.Active;
    mapping(address => uint256) public contributions;
    IAonGoalReached public goalReachedStrategy;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address payable _creator,
        uint256 _goal,
        uint32 _durationInSeconds,
        address _goalReachedStrategy,
        uint32 _claimWindow,
        uint32 _refundWindow
    ) public initializer {
        if (_goal == 0 ether) revert InvalidGoal();
        if (_durationInSeconds < 60 minutes) revert InvalidDuration();
        if (_claimWindow < 60 minutes) revert InvalidClaimWindow();
        if (_refundWindow < 60 minutes) revert InvalidRefundWindow();
        if (_goalReachedStrategy == address(0)) revert InvalidGoalReachedStrategy();
        if (_creator == address(0)) revert InvalidCreator();

        creator = _creator;
        goal = _goal;
        endTime = block.timestamp + _durationInSeconds;
        claimWindow = _claimWindow;
        refundWindow = _refundWindow;
        goalReachedStrategy = IAonGoalReached(_goalReachedStrategy);
        factory = IFactory(msg.sender);

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

    function goalBalance() public view returns (uint256) {
        return address(this).balance - totalContributorFee;
    }

    /// @notice Returns the amount of funds available for the creator to claim.
    function claimableBalance() public view returns (uint256) {
        return address(this).balance - totalCreatorFee - totalContributorFee;
    }

    /*
    * Derived State Functions
    */

    /**
     * @notice Returns true if the contract is finalized.
     * @dev The contract is finalized if the balance is 0, the deadline is reached and both the claim and refund windows have expired.
     *  (ie: the contract has been claimed, fully refunded or swiped)
     * @return true if the contract is finalized, false otherwise.
     */
    function isFinalized() internal view returns (bool) {
        // slither-disable-next-line timestamp
        return (address(this).balance == 0 && block.timestamp > (endTime + claimWindow + refundWindow));
    }

    function isCancelled() internal view returns (bool) {
        return status == Status.Cancelled;
    }

    function isClaimed() internal view returns (bool) {
        return status == Status.Claimed;
    }

    // slither-disable-next-line timestamp
    function isUnclaimed() public view returns (bool) {
        // This is HORRIBLE. Why would you check status === Status.Unclaimed twice?
        // Check stored status first - if already set to Unclaimed, return true
        if (status == Status.Unclaimed) return true;

        // Otherwise derive from current state
        return _isUnclaimed(goalReachedStrategy.isGoalReached());
    }

    /// @dev Internal version that accepts cached goalReached value to avoid redundant external calls
    // slither-disable-next-line timestamp
    function _isUnclaimed(bool goalReached) internal view returns (bool) {
        // slither-disable-next-line timestamp
        return status == Status.Unclaimed || (block.timestamp > endTime + claimWindow && goalReached);
    }

    // slither-disable-next-line timestamp
    function isFailed() internal view returns (bool) {
        return _isFailed(goalReachedStrategy.isGoalReached());
    }

    /// @dev Internal version that accepts cached goalReached value to avoid redundant external calls
    // slither-disable-next-line timestamp
    function _isFailed(bool goalReached) internal view returns (bool) {
        // slither-disable-next-line timestamp
        return (block.timestamp > endTime && !goalReached);
    }

    /// @notice Returns the derived status of the contract. Meant for external use (eg: showing status in UIs).
    function getStatus() external view returns (Status) {
        // Finalized: contract empty and all windows expired - no actions possible
        if (isFinalized()) return Status.Finalized;

        // Check stored terminal states
        if (isCancelled()) return Status.Cancelled;
        if (isClaimed()) return Status.Claimed;

        // Active - derive actual state from goal and time
        bool goalReached = goalReachedStrategy.isGoalReached();

        if (_isUnclaimed(goalReached)) return Status.Unclaimed;
        if (_isFailed(goalReached)) return Status.Failed;

        if (goalReached) return Status.Successful;

        return Status.Active;
    }

    /*
    * Validation Functions
    */
    function getRefundAmount(address contributor, uint256 processingFee) public view returns (uint256) {
        if (isClaimed()) revert CannotRefundClaimedContract();

        bool goalReached = goalReachedStrategy.isGoalReached();

        uint256 refundAmount = contributions[contributor];
        if (refundAmount <= 0) revert CannotRefundZeroContribution();
        if (processingFee > refundAmount) revert ProcessingFeeHigherThanRefundAmount(refundAmount, processingFee);

        refundAmount -= processingFee;

        uint256 _goalBalance = goalBalance();

        /*
            A refund  can be claimed before the goal is reached, or if the refund would not cause the balance to drop
            below the goal (unless the contract is unclaimed).
        */
        if (goalReached && _goalBalance - refundAmount < goal && !_isUnclaimed(goalReached)) {
            revert InsufficientBalanceForRefund(_goalBalance, refundAmount, goal);
        }

        if (isCancelled() || _isFailed(goalReached) || _isUnclaimed(goalReached) || !goalReached) {
            return refundAmount;
        }

        return 0;
    }

    function isValidClaim() private view {
        if (isCancelled()) revert CannotClaimCancelledContract();
        if (isClaimed()) revert AlreadyClaimed();

        // Cache the external call result to avoid multiple expensive calls
        bool goalReached = goalReachedStrategy.isGoalReached();

        if (_isFailed(goalReached)) revert CannotClaimFailedContract();
        if (block.timestamp > endTime + claimWindow) revert CannotClaimAfterClaimWindow();
        if (!goalReached) revert GoalNotReached();
    }

    function canClaim(address _address) public view returns (uint256) {
        if (_address != creator) revert OnlyCreatorCanClaim();
        isValidClaim();

        uint256 creatorAmount = claimableBalance();

        return creatorAmount;
    }

    function getNonce(address _address) external view returns (uint256) {
        return nonces(_address);
    }

    function canCancel() public view returns (bool) {
        if (isCancelled()) revert CannotCancelCancelledContract();
        if (isClaimed()) revert CannotCancelClaimedContract();
        if (isFinalized()) revert CannotCancelFinalizedContract();

        bool isFactoryCall = msg.sender == factory.owner();
        bool isCreatorCall = msg.sender == creator;

        if (!isFactoryCall && !isCreatorCall) revert OnlyCreatorOrFactoryOwnerCanCancel();

        return true;
    }

    function isValidContribution(uint256 _amount, uint256 _contributorFee) public view {
        // slither-disable-next-line timestamp
        if (block.timestamp > endTime) revert CannotContributeAfterEndTime();
        if (isCancelled()) revert CannotContributeToCancelledContract();
        if (isClaimed()) revert CannotContributeToClaimedContract();
        if (isFinalized()) revert CannotContributeToFinalizedContract();
        if (_amount == 0) revert InvalidContribution();
        if (_contributorFee >= _amount) revert ContributorFeeCannotExceedContributionAmount();
    }

    function isValidSwipe() public view {
        // slither-disable-next-line timestamp
        /*
         Swiping funds is only allowed after both the claim and refund windows have expired.
         This is to give ample time for the creator or contributors to get their funds.
        */
        if (block.timestamp <= endTime + claimWindow + refundWindow) {
            revert CannotSwipeFundsBeforeEndOfClaimOrRefundWindow();
        }

        if (address(this).balance == 0) revert NoFundsToSwipe();
    }

    /*
    * EXTERNAL FUNCTIONS
    */

    /**
     * @notice Contribute to the campaign on behalf of a contributor.
     *         Used for contributions that go through a swap contract.
     *
     * @param contributor The address that originally contributed.
     * @param creatorFee The creator fee. The creator fee is deducted from the amount claimed by the creator, but is refunded
     * in case the campaign is cancelled or fails.
     * @param contributorFee The contributor fee. The contributor fee is deducted from the amount refunded to the contributor. It
     *  can include fees like the payment processing fee, a platform tip, etc.
     */
    function contributeFor(address contributor, uint256 creatorFee, uint256 contributorFee) public payable {
        isValidContribution(msg.value, contributorFee);

        // IMPORTANT
        // creatorFee is never validated. This allows me to send 1 wei to this function. uint256.max as creatorFee parameter and deadlock the entire contract

        uint256 contributionAmount = msg.value - contributorFee;
        contributions[contributor] += contributionAmount;
        totalCreatorFee += creatorFee;
        totalContributorFee += contributorFee;

        emit ContributionReceived(contributor, contributionAmount);
    }

    /**
     * @notice Contribute to the campaign for the sender.
     */
    function contribute(uint256 fee, uint256 tip) external payable {
        contributeFor(msg.sender, fee, tip);
    }

    function prepareRefund(address contributor, uint256 processingFee) internal returns (uint256) {
        bool goalReached = goalReachedStrategy.isGoalReached();

        // Is this needed? Would _isUnclaimed by itself not be sufficient?
        /*
            Set the status to Unclaimed so that the status doesn't depend on the balance anymore, and the refunds can
            continue going through even if the balance drops below the goal.
        */
        if (status != Status.Unclaimed && _isUnclaimed(goalReached)) {
            status = Status.Unclaimed;
        }
        uint256 refundAmount = getRefundAmount(contributor, processingFee);

        return refundAmount;
    }

    /**
     * @notice Refund the sender's contributions. Used to refund contributions directly on Rootstock.
     */
    function refund(uint256 processingFee) external {
        uint256 refundAmount = prepareRefund(msg.sender, processingFee);

        contributions[msg.sender] = 0;
        emit ContributionRefunded(msg.sender, refundAmount);

        // Send processing fee to fee recipient
        if (processingFee > 0) {
            (bool success, bytes memory reason) = factory.feeRecipient().call{value: processingFee}("");
            require(success, FailedToSendFeeRecipientAmount(reason));
        }

        // We refund the contributor
        // slither-disable-next-line low-level-calls
        if (refundAmount > 0) {
            (bool success, bytes memory reason) = msg.sender.call{value: refundAmount}("");
            require(success, FailedToRefund(reason));
        }
    }

    /**
     * @notice Refund contributions on behalf of a contributor using an EIP-712
     *         signed message. Funds are sent to the specified swap contract.
     *         Used for refunds that need to go through a swap contract.
     *
     * @param contributor The address that originally contributed and signed
     *                    the permit.
     * @param swapContract The address where the refunded funds will be sent.
     * @param deadline    Timestamp after which the signature is no longer
     *                    valid.
     * @param signature   The EIP-712 signature bytes.
     * @param processingFee The fee for the processing of the refund.
     * @param lockParams  Struct containing swap contract lock parameters.
     */
    function refundToSwapContract(
        address contributor,
        ISwapHTLC swapContract,
        uint256 deadline,
        bytes calldata signature,
        uint256 processingFee,
        SwapContractLockParams calldata lockParams
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (address(swapContract) == address(0)) revert InvalidSwapContract();
        if (lockParams.claimAddress == address(0)) revert InvalidClaimAddress();
        if (lockParams.refundAddress == address(0)) revert InvalidRefundAddress();

        uint256 refundAmount = prepareRefund(contributor, processingFee);

        // IMPORTANT
        // Also needs to include the function signature
        // Worth considering that all parameters (or their hash) are included in the signature to avoid frontrunning to troll and lock funds we won't accept
        verifyEIP712SignatureForRefund(
            contributor,
            swapContract,
            refundAmount,
            deadline,
            processingFee,
            lockParams.preimageHash,
            lockParams.refundAddress,
            signature
        );

        contributions[contributor] = 0;
        emit ContributionRefunded(contributor, refundAmount);

        sendFundsToSwapContract(swapContract, refundAmount, processingFee, lockParams);
    }

    function verifyEIP712SignatureForRefund(
        address contributor,
        ISwapHTLC swapContract,
        uint256 refundAmount,
        uint256 deadline,
        uint256 processingFee,
        bytes32 preimageHash,
        address refundAddress,
        bytes calldata signature
    ) private {
        uint256 nonce = nonces(contributor);
        bytes32 structHash = keccak256(
            abi.encode(
                _REFUND_TO_SWAP_CONTRACT_TYPEHASH,
                contributor,
                swapContract,
                refundAmount,
                nonce,
                deadline,
                processingFee,
                preimageHash,
                refundAddress
            )
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(_DOMAIN_SEPARATOR, structHash);
        address signer = ECDSA.recover(digest, signature);

        require(signer == contributor, InvalidSignature());
        _useNonce(contributor);
    }

    function claim(uint256 processingFee) external {
        // processingFee also needs to be validated
        totalCreatorFee += processingFee;
        uint256 creatorAmount = canClaim(msg.sender);
        status = Status.Claimed;

        emit Claimed(creatorAmount, totalCreatorFee, totalContributorFee);

        // Send platform fees
        uint256 totalPlatformAmount = totalCreatorFee + totalContributorFee;
        if (totalPlatformAmount > 0) {
            // slither-disable-next-line low-level-calls
            (bool success, bytes memory reason) = factory.feeRecipient().call{value: totalPlatformAmount}("");
            require(success, FailedToSendFeeRecipientAmount(reason));
        }

        // Send remaining funds to creator
        if (creatorAmount > 0) {
            // slither-disable-next-line low-level-calls
            (bool success, bytes memory reason) = creator.call{value: creatorAmount}("");
            require(success, FailedToSendFundsInClaim(reason));
        }
    }

    /**
     * @notice Claim all funds on behalf of the creator using an EIP-712
     *         signed message. Funds are sent to the specified swap contract.
     *
     * @param swapContract The address where the claimed funds will be sent.
     * @param deadline    Timestamp after which the signature is no longer
     *                    valid.
     * @param signature   The EIP-712 signature bytes.
     * @param processingFee The fee for the processing of the claim.
     * @param lockParams  Struct containing swap contract lock parameters.
     */
    function claimToSwapContract(
        ISwapHTLC swapContract,
        uint256 deadline,
        bytes calldata signature,
        uint256 processingFee,
        SwapContractLockParams calldata lockParams
    ) external {
        // Modifying state before doing checks is bad practice. Makes failed transactions more expensive for no reason
        // 1. Checks
        // 2. Effects
        // 3. Interactions
        totalCreatorFee += processingFee;

        if (block.timestamp > deadline) revert SignatureExpired();
        if (address(swapContract) == address(0)) revert InvalidSwapContract();
        if (lockParams.claimAddress == address(0)) revert InvalidClaimAddress();
        if (lockParams.refundAddress == address(0)) revert InvalidRefundAddress();

        isValidClaim();
        uint256 claimableAmount = claimableBalance();

        // IMPORTANT
        // Also needs to include the function signature
        verifyEIP712SignatureForClaim(
            swapContract,
            claimableAmount,
            deadline,
            processingFee,
            lockParams.preimageHash,
            lockParams.refundAddress,
            signature
        );

        status = Status.Claimed;
        emit Claimed(claimableAmount, totalCreatorFee, totalContributorFee);

        sendFundsToSwapContract(swapContract, claimableAmount, totalCreatorFee + totalContributorFee, lockParams);
    }

    function cancel() external {
        canCancel();
        status = Status.Cancelled;
        emit Cancelled();
    }

    function swipeFunds() public {
        // OnlyFactoryCanSwipeFunds can be removed if you want everyone to be able to swipe
        // There are  bunch of unused errors
        // The inconsistency of those "isSmthg" functions that sometimes return a bool but also revert is beyond me but alright
        isValidSwipe();

        // Send fees to fee recipient: both fees if unclaimed, otherwise only contributor fees
        uint256 fees = isUnclaimed() ? totalCreatorFee + totalContributorFee : totalContributorFee;
        uint256 recipientAmount = address(this).balance - fees;
        address payable swipeRecipient = factory.swipeRecipient();

        emit FundsSwiped(swipeRecipient, fees, recipientAmount);

        if (fees > 0) {
            (bool feeSent, bytes memory feeReason) = factory.feeRecipient().call{value: fees}("");
            require(feeSent, FailedToSendFeeRecipientAmount(feeReason));
        }

        // Send everything (remaining) to recipient
        if (recipientAmount > 0) {
            (bool sent, bytes memory reason) = swipeRecipient.call{value: recipientAmount}("");
            require(sent, FailedToSwipeFunds(reason));
        }
    }

    function verifyEIP712SignatureForClaim(
        ISwapHTLC swapContract,
        uint256 claimableAmount,
        uint256 deadline,
        uint256 processingFee,
        bytes32 preimageHash,
        address refundAddress,
        bytes calldata signature
    ) private {
        uint256 nonce = nonces(creator);
        bytes32 structHash = keccak256(
            abi.encode(
                _CLAIM_TO_SWAP_CONTRACT_TYPEHASH,
                creator,
                swapContract,
                claimableAmount,
                nonce,
                deadline,
                processingFee,
                preimageHash,
                refundAddress
            )
        );

        bytes32 digest = MessageHashUtils.toTypedDataHash(_DOMAIN_SEPARATOR, structHash);
        address signer = ECDSA.recover(digest, signature);

        require(signer == creator, InvalidSignature());
        _useNonce(creator);
    }

    function sendFundsToSwapContract(
        ISwapHTLC swapContract,
        uint256 amount,
        uint256 feeRecipientAmount,
        SwapContractLockParams calldata lockParams
    ) private {
        if (feeRecipientAmount > 0) {
            (bool success, bytes memory reason) = factory.feeRecipient().call{value: feeRecipientAmount}("");
            require(success, FailedToSendFeeRecipientAmount(reason));
        }

        // Send remaining funds to swap contract
        if (amount > 0) {
            // slither-disable-next-line low-level-calls
            (bool success, bytes memory reason) = address(swapContract).call{value: amount}(
                abi.encodeWithSignature(
                    lockParams.functionSignature,
                    lockParams.preimageHash,
                    lockParams.claimAddress,
                    lockParams.refundAddress,
                    lockParams.timelock
                )
            );
            require(success, FailedToSendFundsInClaim(reason));
        }
    }
}
