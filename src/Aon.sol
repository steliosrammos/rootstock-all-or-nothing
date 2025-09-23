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

contract Aon is Initializable, Nonces {
    /*
    * EVENTS
    */
    // Contract events
    event Claimed(uint256 creatorAmount, uint256 creatorFeeAmount, uint256 contributorFeeAmount);
    event Cancelled();
    event FundsSwiped();

    // Contribution events
    event ContributionRefunded(address indexed contributor, uint256 amount);
    event ContributionReceived(address indexed contributor, uint256 amount);

    error GoalNotReached();
    error GoalReachedAlready();
    error InvalidContribution();
    error FailedToSwipeFunds(bytes reason);
    error AlreadyClaimed();

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
    error FailedToSendPlatformAmount(bytes reason);

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
    bytes32 private constant _REFUND_TO_SWAP_CONTRACT_TYPEHASH =
        keccak256("Refund(address contributor,address swapContract,uint256 amount,uint256 nonce,uint256 deadline)");
    bytes32 private constant _CLAIM_TO_SWAP_CONTRACT_TYPEHASH =
        keccak256("Claim(address creator,address swapContract,uint256 amount,uint256 nonce,uint256 deadline)");

    // Cached domain separator built in `initialize`
    bytes32 private _DOMAIN_SEPARATOR;

    /*
    * STATE VARIABLES
    */
    IOwnable public factory;
    address payable public creator;
    uint256 public goal;
    uint256 public endTime;
    uint256 public totalCreatorFee;
    uint256 public totalContributorFee;
    uint256 public claimOrRefundWindow;

    /*
    * The status is only updated to Active, Cancelled or Claimed, other statuses are derived from contract state
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
        uint256 _durationInSeconds,
        address _goalReachedStrategy,
        uint256 _claimOrRefundWindow
    ) public initializer {
        creator = _creator;
        goal = _goal;
        endTime = block.timestamp + _durationInSeconds;
        claimOrRefundWindow = _claimOrRefundWindow;
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

    function goalBalance() external view returns (uint256) {
        return address(this).balance - totalContributorFee;
    }

    /// @notice Returns the amount of funds available for the creator to claim.
    function claimableBalance() public view returns (uint256) {
        return address(this).balance - totalCreatorFee - totalContributorFee;
    }

    /// @notice Returns true if the address is the creator of the AON campaign.
    function isCreator(address _address) public view returns (bool) {
        return _address == creator;
    }

    /*
    * Derived State Functions
    */
    function isFinalized() internal view returns (bool) {
        return (address(this).balance == 0 && block.timestamp > (endTime + claimOrRefundWindow * 2));
    }

    function isCancelled() internal view returns (bool) {
        return status == Status.Cancelled;
    }

    function isClaimed() internal view returns (bool) {
        return status == Status.Claimed;
    }

    function isUnclaimed() public view returns (bool) {
        return (block.timestamp > endTime + claimOrRefundWindow && goalReachedStrategy.isGoalReached());
    }

    function isFailed() public view returns (bool) {
        return (block.timestamp > endTime && !goalReachedStrategy.isGoalReached());
    }

    function isSuccessful() public view returns (bool) {
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

    function canClaim(address _address) public view returns (uint256, uint256) {
        if (!isCreator(_address)) revert OnlyCreatorCanClaim();
        isValidClaim();

        uint256 nonce = nonces(_address);
        uint256 creatorAmount = claimableBalance();

        return (creatorAmount, nonce);
    }

    function canClaimToSwapContract() internal view returns (uint256) {
        isValidClaim();

        uint256 creatorAmount = claimableBalance();
        return (creatorAmount);
    }

    function canCancel() public view returns (bool) {
        if (isCancelled()) revert CannotCancelCancelledContract();
        if (isClaimed()) revert CannotCancelClaimedContract();
        if (isFinalized()) revert CannotCancelFinalizedContract();

        bool isFactoryCall = msg.sender == factory.owner();
        bool isCreatorCall = isCreator(msg.sender);

        if (!isFactoryCall && !isCreatorCall) revert OnlyCreatorOrFactoryOwnerCanCancel();

        return true;
    }

    function isValidContribution(uint256 _amount, uint256 _contributorFee) public view {
        if (block.timestamp > endTime) revert CannotContributeAfterEndTime();
        if (isCancelled()) revert CannotContributeToCancelledContract();
        if (isClaimed()) revert CannotContributeToClaimedContract();
        if (isFinalized()) revert CannotContributeToFinalizedContract();
        if (_amount == 0) revert InvalidContribution();
        if (_contributorFee >= _amount) revert ContributorFeeCannotExceedContributionAmount();
    }

    function isValidSwipe() public view returns (bool) {
        if (msg.sender != factory.owner()) revert OnlyFactoryCanSwipeFunds();

        /*
            We take the claim/refund twice as the max delay, in case the funds were not claimed by the creator 
            (claim window) and then some funds were not refunded (refund window).
        */
        if (block.timestamp <= endTime + claimOrRefundWindow * 2) {
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

        contributions[msg.sender] = 0;

        // We refund the contributor
        (bool success, bytes memory reason) = msg.sender.call{value: refundAmount}("");
        require(success, FailedToRefund(reason));

        emit ContributionRefunded(msg.sender, refundAmount);
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
     * @param preimageHash The preimage hash for the lock.
     * @param claimAddress The address that can claim the locked funds.
     * @param timelock     The timelock value for the lock.
     * @param processingFee The fee for the processing of the refund.
     */
    function refundToSwapContract(
        address contributor,
        address swapContract,
        uint256 deadline,
        bytes calldata signature,
        bytes32 preimageHash,
        address claimAddress,
        uint256 timelock,
        uint256 processingFee
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();

        (uint256 refundAmount, uint256 nonce) = isValidRefund(contributor, processingFee);

        // -----------------------------------------------------------------
        // Verify EIP-712 signature
        // -----------------------------------------------------------------
        verifyEIP712SignatureForRefund(contributor, swapContract, refundAmount, nonce, deadline, signature);

        // Consume nonce to prevent replay
        _useNonce(contributor);

        // -----------------------------------------------------------------
        // Execute refund
        // -----------------------------------------------------------------
        contributions[contributor] = 0;

        (bool success, bytes memory reason) = swapContract.call{value: refundAmount}(
            abi.encodeWithSignature("lock(bytes32,address,uint256)", preimageHash, claimAddress, timelock)
        );
        require(success, FailedToRefund(reason));

        emit ContributionRefunded(contributor, refundAmount);
    }

    function verifyEIP712SignatureForRefund(
        address contributor,
        address swapContract,
        uint256 refundAmount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) private view {
        bytes32 structHash = keccak256(
            abi.encode(_REFUND_TO_SWAP_CONTRACT_TYPEHASH, contributor, swapContract, refundAmount, nonce, deadline)
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(_DOMAIN_SEPARATOR, structHash);
        address signer = ECDSA.recover(digest, signature);

        require(signer == contributor, InvalidSignature());
    }

    function claim() external {
        (uint256 creatorAmount,) = canClaim(msg.sender);
        status = Status.Claimed;

        // Send platform fees
        uint256 totalPlatformAmount = totalCreatorFee + totalContributorFee;
        if (totalPlatformAmount > 0) {
            (bool success, bytes memory reason) = factory.owner().call{value: totalPlatformAmount}("");
            require(success, FailedToSendPlatformAmount(reason));
        }

        // Send remaining funds to creator
        if (creatorAmount > 0) {
            (bool success, bytes memory reason) = creator.call{value: creatorAmount}("");
            require(success, FailedToSendFundsInClaim(reason));
        }

        emit Claimed(creatorAmount, totalCreatorFee, totalContributorFee);
    }

    /**
     * @notice Claim all funds on behalf of the creator using an EIP-712
     *         signed message. Funds are sent to the specified swap contract.
     *
     * @param swapContract The address where the claimed funds will be sent.
     * @param deadline    Timestamp after which the signature is no longer
     *                    valid.
     * @param signature   The EIP-712 signature bytes.
     * @param preimageHash The preimage hash for the lock.
     * @param claimAddress The address that can claim the locked funds.
     * @param timelock     The timelock value for the lock.
     */
    function claimToSwapContract(
        address swapContract,
        uint256 deadline,
        bytes calldata signature,
        bytes32 preimageHash,
        address claimAddress,
        uint256 timelock
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();

        (uint256 creatorAmount) = canClaimToSwapContract();

        // Verify signature
        verifyClaimSignature(swapContract, deadline, signature);

        // Execute claim
        executeClaimToSwapContract(swapContract, creatorAmount, preimageHash, claimAddress, timelock);
    }

    function cancel() external {
        canCancel();
        status = Status.Cancelled;
        emit Cancelled();
    }

    function swipeFunds() public {
        isValidSwipe();

        (bool success, bytes memory reason) = factory.owner().call{value: address(this).balance}("");
        require(success, FailedToSwipeFunds(reason));

        emit FundsSwiped();
    }

    /*
    * Private Functions
    */
    function verifyClaimSignature(address swapContract, uint256 deadline, bytes calldata signature) private {
        uint256 nonce = nonces(creator);
        bytes32 structHash = keccak256(
            abi.encode(_CLAIM_TO_SWAP_CONTRACT_TYPEHASH, creator, swapContract, address(this).balance, nonce, deadline)
        );

        bytes32 digest = MessageHashUtils.toTypedDataHash(_DOMAIN_SEPARATOR, structHash);
        address signer = ECDSA.recover(digest, signature);

        require(signer == creator, InvalidSignature());
        _useNonce(creator);
    }

    function executeClaimToSwapContract(
        address swapContract,
        uint256 creatorAmount,
        bytes32 preimageHash,
        address claimAddress,
        uint256 timelock
    ) private {
        status = Status.Claimed;

        // Send platform fees and tips
        uint256 totalPlatformAmount = totalCreatorFee + totalContributorFee;
        if (totalPlatformAmount > 0) {
            (bool success, bytes memory reason) = factory.owner().call{value: totalPlatformAmount}("");
            require(success, FailedToSendPlatformAmount(reason));
        }

        // Send remaining funds to swap contract
        if (creatorAmount > 0) {
            (bool success, bytes memory reason) = swapContract.call{value: creatorAmount}(
                abi.encodeWithSignature("lock(bytes32,address,uint256)", preimageHash, claimAddress, timelock)
            );
            require(success, FailedToSendFundsInClaim(reason));
        }

        emit Claimed(creatorAmount, totalCreatorFee, totalContributorFee);
    }
}
