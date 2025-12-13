// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./AonProxy.sol";
import "./Aon.sol";

contract Factory is Ownable {
    event AonCreated(address contractAddress);

    address public implementation;
    address payable public swipeRecipient;
    address payable public feeRecipient;

    error InvalidImplementation();
    error InvalidSwipeRecipient();
    error InvalidFeeRecipient();

    constructor(address _implementation, address payable _swipeRecipient, address payable _feeRecipient, address _owner)
        Ownable(_owner)
    {
        if (_implementation == address(0)) revert InvalidImplementation();
        if (_swipeRecipient == address(0)) revert InvalidSwipeRecipient();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();
        implementation = _implementation;
        swipeRecipient = _swipeRecipient;
        feeRecipient = _feeRecipient;
    }

    function setImplementation(address _implementation) public onlyOwner {
        if (_implementation == address(0)) revert InvalidImplementation();
        implementation = _implementation;
    }

    function setSwipeRecipient(address payable _swipeRecipient) public onlyOwner {
        if (_swipeRecipient == address(0)) revert InvalidSwipeRecipient();
        swipeRecipient = _swipeRecipient;
    }

    function setFeeRecipient(address payable _feeRecipient) public onlyOwner {
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Deploys a new Aon contract.
     * @param creator The crowdfunding campaign creator.
     * @param goalInEther The crowdfunding goal in wei.
     * @param durationInSeconds Campaign duration in seconds.
     * @param goalReachedStrategy Address of the goal reached strategy contract.
     * @param claimWindow The time period (in seconds) after campaign end during which the creator can claim.
     * @param refundWindow The time period (in seconds) during which contributors can request refunds after the campaign ends or after the claim window.
     */
    function create(
        address payable creator,
        // The goal is not in ether, but in WEI
        // And might not even be WEI in the future if you do different goal strategies
        uint256 goalInEther,
        uint32 durationInSeconds,
        address goalReachedStrategy,
        uint32 claimWindow,
        uint32 refundWindow
    ) external {
        AonProxy proxy = new AonProxy(implementation);
        emit AonCreated(address(proxy));
        Aon(address(proxy))
            .initialize(creator, goalInEther, durationInSeconds, goalReachedStrategy, claimWindow, refundWindow);
    }
}
