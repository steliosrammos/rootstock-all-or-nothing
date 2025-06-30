// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./AonProxy.sol";
import "./Aon.sol";

contract Factory is Ownable {
    event AonCreated(address contractAddress);

    address public implementation;

    constructor(address _implementation) Ownable(msg.sender) {
        implementation = _implementation;
    }

    function setImplementation(address _implementation) public onlyOwner {
        implementation = _implementation;
    }

    function create(address payable _creator, uint256 _goal, uint256 _durationInSeconds, address _goalReachedStrategy)
        external
        onlyOwner
    {
        AonProxy proxy = new AonProxy(implementation);
        Aon(address(proxy)).initialize(_creator, _goal, _durationInSeconds, _goalReachedStrategy);
        emit AonCreated(address(proxy));
    }
}
