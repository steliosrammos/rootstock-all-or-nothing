// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IOwnable {
    function owner() external view returns (address);
}

contract Aon {
    error GoalNotReached();
    error GoalReachedAlready();
    error InvalidContribution();
    error FailedToSendEther();

    address payable public immutable creator;
    uint256 public immutable goal;

    IOwnable public immutable factory;

    mapping(address => uint256) public contributions;

    constructor() {
        factory = IOwnable(msg.sender);
    }

    function claim() external {
        require(goalReached(), GoalNotReached());

        (bool success, ) = creator.call{value: address(this).balance}("");
        require(success, FailedToSendEther());
    }

    function contribute() external payable {
        require(!goalReached(), GoalReachedAlready());
        require(msg.value > 0, InvalidContribution());

        contributions[msg.sender] += msg.value;
    }

    function cancel() external {
        require(msg.sender == factory.owner(), "Only factory can cancel");
        selfdestruct(payable(factory.owner()));
    }

    function goalReached() public view returns (bool) {
        return address(this).balance >= goal;
    }
}
