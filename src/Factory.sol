// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./AonProxy.sol";
import "./Aon.sol";

contract Factory is Ownable {
    event AonCreated(address contractAddress);

    address public implementation;

    error InvalidImplementation();

    constructor(address _implementation) Ownable(msg.sender) {
        if (_implementation == address(0)) revert InvalidImplementation();
        implementation = _implementation;
    }

    function setImplementation(address _implementation) public onlyOwner {
        if (_implementation == address(0)) revert InvalidImplementation();
        implementation = _implementation;
    }

    function create(
        address payable creator,
        uint256 goalInEther,
        uint256 durationInSeconds,
        address goalReachedStrategy,
        uint256 claimOrRefundWindow
    ) external {
        AonProxy proxy = new AonProxy(implementation);
        emit AonCreated(address(proxy));
        Aon(address(proxy)).initialize(
            creator, goalInEther, durationInSeconds, goalReachedStrategy, claimOrRefundWindow
        );
    }
}
