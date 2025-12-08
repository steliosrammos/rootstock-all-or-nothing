// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/Aon.sol";
import "../../src/AonProxy.sol";
import "../../src/AonGoalReachedNative.sol";

/// @notice Base test contract for all Aon tests
/// @dev Contains common setup, state variables, constants, and helper functions
abstract contract AonTestBase is Test {
    // State variables
    Aon public aon;
    AonGoalReachedNative public goalReachedStrategy;

    address payable public creator;
    uint256 public creatorPrivateKey;

    address payable public contributor1;
    uint256 public contributor1PrivateKey;

    address payable public contributor2;
    address public factoryOwner;
    address public randomAddress;
    address payable public feeRecipient;
    address payable public swipeRecipient;

    // Constants
    uint256 public constant GOAL = 10 ether;
    uint32 public constant DURATION = 30 days;
    uint256 public constant PLATFORM_FEE = 250; // 2.5% in basis points
    uint256 public constant CONTRIBUTION_AMOUNT = 1 ether;
    uint256 public constant PROCESSING_FEE = 0.1 ether;

    // Events
    event ContributionReceived(address indexed contributor, uint256 amount);
    event ContributionRefunded(address indexed contributor, uint256 amount);
    event Claimed(uint256 creatorAmount, uint256 creatorFeeAmount, uint256 contributorFeeAmount);
    event Cancelled();
    event Refunded();
    event FundsSwiped(address recipient, uint256 feeRecipientAmount, uint256 recipientAmount);

    function setUp() public virtual {
        (address _creator, uint256 _creatorPrivateKey) = makeAddrAndKey("creator");
        creator = payable(_creator);
        creatorPrivateKey = _creatorPrivateKey;

        (address _contributor1, uint256 _contributor1PrivateKey) = makeAddrAndKey("contributor1");
        contributor1 = payable(_contributor1);
        contributor1PrivateKey = _contributor1PrivateKey;

        contributor2 = payable(makeAddr("contributor2"));
        factoryOwner = address(this);
        randomAddress = makeAddr("random");
        feeRecipient = payable(makeAddr("feeRecipient"));
        swipeRecipient = payable(makeAddr("swipeRecipient"));

        goalReachedStrategy = new AonGoalReachedNative();

        // Deploy implementation and proxy
        Aon implementation = new Aon();
        AonProxy proxy = new AonProxy(address(implementation));
        aon = Aon(address(proxy));

        // Initialize contract via proxy
        vm.prank(factoryOwner);
        aon.initialize(
            creator, GOAL, DURATION, address(goalReachedStrategy), 30 days, 30 days, feeRecipient, swipeRecipient
        );

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

    // Helper functions for signature creation (used in refund and claim tests)
    function _createRefundSignature(
        address contributor,
        address swapContract,
        uint256 amount,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        return _createRefundSignatureWithFeeAndRefundAddress(
            contributor, swapContract, amount, deadline, 0, bytes32(0), address(0x456), privateKey
        );
    }

    function _createRefundSignatureWithFee(
        address contributor,
        address swapContract,
        uint256 amount,
        uint256 deadline,
        uint256 processingFee,
        bytes32 preimageHash,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        return _createRefundSignatureWithFeeAndRefundAddress(
            contributor, swapContract, amount, deadline, processingFee, preimageHash, address(0x456), privateKey
        );
    }

    function _createRefundSignatureWithFeeAndRefundAddress(
        address contributor,
        address swapContract,
        uint256 amount,
        uint256 deadline,
        uint256 processingFee,
        bytes32 preimageHash,
        address refundAddress,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        uint256 nonce = aon.nonces(contributor);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Refund(address contributor,address swapContract,uint256 amount,uint256 nonce,uint256 deadline,uint256 processingFee,bytes32 preimageHash,address refundAddress)"
                ),
                contributor,
                swapContract,
                amount,
                nonce,
                deadline,
                processingFee,
                preimageHash,
                refundAddress
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", aon.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}

/// @dev A helper contract to test re-entrancy protection on the refund function.
contract MaliciousRefund {
    Aon public immutable aon;

    constructor(Aon _aon) {
        aon = _aon;
    }

    function contribute(uint256 fee, uint256 contributorFee) external payable {
        aon.contribute{value: msg.value}(fee, contributorFee);
    }

    function startAttack() external {
        aon.refund(0);
    }

    // This function is called when the contract receives Ether.
    // It will try to call refund() again, exploiting a potential re-entrancy vulnerability.
    receive() external payable {
        // The re-entrant call should fail if the contract is secure.
        aon.refund(0);
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
        Aon public aon;

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

