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
     * @param timelock The timelock value in seconds
     * @dev This function should be payable to receive the locked funds
     */
    function lock(bytes32 preimageHash, address claimAddress, uint256 timelock) external payable;
}

contract Aon is Initializable, Nonces {
    /*
    * EVENTS
    */
    // Contract events
    event Claimed(uint256 creatorAmount, uint256 creatorFeeAmount, uint256 contributorFeeAmount);
    event Cancelled();
    event FundsSwiped(address recipient);

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
    error InvalidFeeRecipient();

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
    error CannotClaimUnclaimedContract();
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
        bytes32 preimageHash;
        address claimAddress;
        address refundAddress;
        uint256 timelock;
        string functionSignature;
    }

    // Status enum
    enum Status {
        Active, // 0 - Default active state
        Cancelled, // 1 - Campaign cancelled
        Claimed, // 2 - Funds claimed by creator
        Successful, // 3 - Goal reached and claim window expired
        Failed, // 4 - Time expired without reaching goal
        Finalized // 5 - All operations complete, contract can be cleaned up
    }

    // ---------------------------------------------------------------------
    // EIP-712 CONSTANTS & STATE
    // ---------------------------------------------------------------------

    // solhint-disable-next-line max-line-length
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _REFUND_TO_SWAP_CONTRACT_TYPEHASH = keccak256(
        "Refund(address contributor,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 preimageHash)"
    );
    bytes32 private constant _CLAIM_TO_SWAP_CONTRACT_TYPEHASH = keccak256(
        "Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 preimageHash)"
    );

    // Cached domain separator built in `initialize`
    bytes32 private _DOMAIN_SEPARATOR;

    /*
    * STATE VARIABLES
    */
    IOwnable public factory;
    address payable public creator;
    address payable public feeRecipient;
    uint256 public goal;
    uint256 public endTime;
    uint256 public totalCreatorFee;

    uint256 public totalContributorFee;
    uint256 public claimWindow;
    uint256 public refundWindow;

    /*
    * The status is only updated to Active, Cancelled or Claimed, other statuses are derived from contract state
    */
    Status public status = Status.Active;
    mapping(address => uint256) public contributions;
    IAonGoalReached public goalReachedStrategy;

    uint8 public constant VERSION = 1;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address payable _creator,
        uint256 _goal,
        uint256 _durationInSeconds,
        address _goalReachedStrategy,
        uint256 _claimWindow,
        uint256 _refundWindow,
        address payable _feeRecipient
    ) public initializer {
        if (_goal == 0 ether) revert InvalidGoal();
        if (_durationInSeconds < 60 minutes) revert InvalidDuration();
        if (_claimWindow < 60 minutes) revert InvalidClaimWindow();
        if (_refundWindow < 60 minutes) revert InvalidRefundWindow();
        if (_goalReachedStrategy == address(0)) revert InvalidGoalReachedStrategy();
        if (_creator == address(0)) revert InvalidCreator();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();

        creator = _creator;
        goal = _goal;
        endTime = block.timestamp + _durationInSeconds;
        claimWindow = _claimWindow;
        refundWindow = _refundWindow;
        goalReachedStrategy = IAonGoalReached(_goalReachedStrategy);
        factory = IOwnable(msg.sender);
        feeRecipient = _feeRecipient;

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

    function goalBalance() external view returns (uint256) {
        return address(this).balance - totalContributorFee;
    }

    /// @notice Returns the amount of funds available for the creator to claim.
    function claimableBalance() public view returns (uint256) {
        return address(this).balance - totalCreatorFee - totalContributorFee;
    }

    /*
    * Derived State Functions
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
        // slither-disable-next-line timestamp
        return (block.timestamp > endTime + claimWindow && goalReachedStrategy.isGoalReached());
    }

    // slither-disable-next-line timestamp
    function isFailed() internal view returns (bool) {
        // slither-disable-next-line timestamp
        return (block.timestamp > endTime && !goalReachedStrategy.isGoalReached());
    }

    function isSuccessful() internal view returns (bool) {
        return (!isCancelled() && goalReachedStrategy.isGoalReached());
    }

    /// @notice Returns the derived status of the contract. Meant for external use (eg: showing status in UIs).
    function getStatus() external view returns (Status) {
        if (status == Status.Active) {
            if (isFailed()) return Status.Failed;
            if (isSuccessful()) return Status.Successful;
            return Status.Active;
        }
        if (isFinalized()) return Status.Finalized;
        if (isClaimed()) return Status.Claimed;
        if (isCancelled()) return Status.Cancelled;

        return status;
    }

    /*
    * Validation Functions
    */
    function isValidRefund(address contributor, uint256 processingFee) public view returns (uint256, uint256) {
        uint256 refundAmount = contributions[contributor];
        if (refundAmount <= 0) revert CannotRefundZeroContribution();
        if (processingFee > refundAmount) revert ProcessingFeeHigherThanRefundAmount(refundAmount, processingFee);

        refundAmount -= processingFee;

        if (isClaimed()) revert CannotRefundClaimedContract();

        uint256 balance = address(this).balance;

        if (goalReachedStrategy.isGoalReached() && !isUnclaimed() && balance - refundAmount < goal) {
            revert InsufficientBalanceForRefund(balance, refundAmount, goal);
        }

        uint256 nonce = nonces(contributor);

        if (isCancelled() || isFailed() || isUnclaimed() || !goalReachedStrategy.isGoalReached()) {
            return (refundAmount, nonce);
        }

        return (0, nonce);
    }

    function isValidClaim() private view {
        if (isCancelled()) revert CannotClaimCancelledContract();
        if (isClaimed()) revert AlreadyClaimed();
        if (isFailed()) revert CannotClaimFailedContract();
        if (isUnclaimed()) revert CannotClaimUnclaimedContract();
        if (!goalReachedStrategy.isGoalReached()) revert GoalNotReached();
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

    function isValidSwipe() public view returns (bool) {
        if (msg.sender != factory.owner()) revert OnlyFactoryCanSwipeFunds();

        // slither-disable-next-line timestamp
        if (block.timestamp <= endTime + claimWindow + refundWindow) {
            revert CannotSwipeFundsBeforeEndOfClaimOrRefundWindow();
        }

        if (address(this).balance == 0) revert NoFundsToSwipe();

        return true;
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

    /**
     * @notice Refund the sender's contributions. Used to refund contributions directly on Rootstock.
     */
    function refund(uint256 processingFee) external {
        (uint256 refundAmount,) = isValidRefund(msg.sender, processingFee);

        // totalContributorFee += processingFee;

        contributions[msg.sender] = 0;
        emit ContributionRefunded(msg.sender, refundAmount);

        // Send processing fee to fee recipient
        if (processingFee > 0) {
            (bool success, bytes memory reason) = feeRecipient.call{value: processingFee}("");
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

        (uint256 refundAmount, uint256 nonce) = isValidRefund(contributor, processingFee);

        // -----------------------------------------------------------------
        // Verify EIP-712 signature
        // -----------------------------------------------------------------
        verifyEIP712SignatureForRefund(
            contributor, swapContract, deadline, signature, lockParams.preimageHash, processingFee, refundAmount, nonce
        );

        // totalContributorFee += processingFee;

        _useNonce(contributor);
        contributions[contributor] = 0;
        emit ContributionRefunded(contributor, refundAmount);

        sendFundsToSwapContract(swapContract, refundAmount, processingFee, lockParams);
    }

    function verifyEIP712SignatureForRefund(
        address contributor,
        ISwapHTLC swapContract,
        uint256 deadline,
        bytes calldata signature,
        bytes32 preimageHash,
        uint256 processingFee,
        uint256 refundAmount,
        uint256 nonce
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(
                _REFUND_TO_SWAP_CONTRACT_TYPEHASH,
                contributor,
                swapContract,
                refundAmount,
                nonce,
                deadline,
                processingFee,
                preimageHash
            )
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(_DOMAIN_SEPARATOR, structHash);
        address signer = ECDSA.recover(digest, signature);

        require(signer == contributor, InvalidSignature());
    }

    function claim(uint256 processingFee) external {
        totalCreatorFee += processingFee;
        uint256 creatorAmount = canClaim(msg.sender);
        status = Status.Claimed;

        emit Claimed(creatorAmount, totalCreatorFee, totalContributorFee);

        // Send platform fees
        uint256 totalPlatformAmount = totalCreatorFee + totalContributorFee;
        if (totalPlatformAmount > 0) {
            // slither-disable-next-line low-level-calls
            (bool success, bytes memory reason) = factory.owner().call{value: totalPlatformAmount}("");
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
        totalCreatorFee += processingFee;

        if (block.timestamp > deadline) revert SignatureExpired();
        if (address(swapContract) == address(0)) revert InvalidSwapContract();
        if (lockParams.claimAddress == address(0)) revert InvalidClaimAddress();
        if (lockParams.refundAddress == address(0)) revert InvalidRefundAddress();

        isValidClaim();
        uint256 creatorAmount = claimableBalance();

        // Verify signature
        verifyClaimSignature(swapContract, creatorAmount, deadline, signature, lockParams.preimageHash, processingFee);

        status = Status.Claimed;
        emit Claimed(creatorAmount, totalCreatorFee, totalContributorFee);

        sendFundsToSwapContract(swapContract, creatorAmount, totalCreatorFee + totalContributorFee, lockParams);
    }

    function cancel() external {
        canCancel();
        status = Status.Cancelled;
        emit Cancelled();
    }

    function swipeFunds(address payable recipient) public {
        isValidSwipe();
        emit FundsSwiped(recipient);

        uint256 contractBalance = address(this).balance;

        // If the contract is unclaimed, send the platform fee and the claimable amount to the fee recipient
        if (this.isUnclaimed()) {
            uint256 claimable = claimableBalance();
            uint256 platformAmount = contractBalance - claimable;

            (bool feeSent, bytes memory feeReason) = feeRecipient.call{value: platformAmount}("");
            require(feeSent, FailedToSendFeeRecipientAmount(feeReason));

            contractBalance = claimable; // Only claimable amount left for recipient
        }

        // Send everything (remaining) to recipient
        (bool sent, bytes memory reason) = recipient.call{value: contractBalance}("");
        require(sent, FailedToSwipeFunds(reason));
    }

    /*
    * Private Functions
    */
    function verifyClaimSignature(
        ISwapHTLC swapContract,
        uint256 _claimableBalance,
        uint256 deadline,
        bytes calldata signature,
        bytes32 preimageHash,
        uint256 processingFee
    ) private {
        uint256 nonce = nonces(creator);
        bytes32 structHash = keccak256(
            abi.encode(
                _CLAIM_TO_SWAP_CONTRACT_TYPEHASH,
                creator,
                swapContract,
                _claimableBalance,
                nonce,
                deadline,
                processingFee,
                preimageHash
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
            (bool success, bytes memory reason) = feeRecipient.call{value: feeRecipientAmount}("");
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
