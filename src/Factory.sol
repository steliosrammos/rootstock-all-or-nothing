// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./AonProxy.sol";
import "./Aon.sol";

contract Factory is Ownable {
    event AonCreated(address contractAddress);

    address public implementation;

    error InvalidImplementation();
    error InvalidOwner();

    constructor(address _implementation, address _owner) Ownable(_owner) {
        if (_implementation == address(0)) revert InvalidImplementation();
        implementation = _implementation;
    }

    function setImplementation(address _implementation) public onlyOwner {
        if (_implementation == address(0)) revert InvalidImplementation();
        implementation = _implementation;
    }

    /**
     * @notice Deploys a new Aon contract.
     * @param creator The crowdfunding campaign creator.
     * @param goalInEther The crowdfunding goal in wei.
     * @param durationInSeconds Campaign duration in seconds.
     * @param goalReachedStrategy Address of the goal reached strategy contract.
     * @param claimWindow The time period (in seconds) after campaign end during which the creator can claim.
     * @param refundWindow The time period (in seconds) during which contributors can request refunds after the campaign ends or after the claim window.
     * @param feeRecipient The address that will receive platform/processing fees (creator and contributor fees).
     */
    function create(
        address payable creator,
        uint256 goalInEther,
        uint32 durationInSeconds,
        address goalReachedStrategy,
        uint32 claimWindow,
        uint32 refundWindow,
        address payable feeRecipient
    ) external {
        AonProxy proxy = new AonProxy(implementation);
        emit AonCreated(address(proxy));
        Aon(address(proxy))
            .initialize(
                creator, goalInEther, durationInSeconds, goalReachedStrategy, claimWindow, refundWindow, feeRecipient
            );
    }
}
