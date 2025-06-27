// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./AonProxy.sol";

contract Factory is Ownable {
    event AonCreated(address contractAddress);

    address public implementation;

    constructor(address _implementation) Ownable(msg.sender) {
        implementation = _implementation;
    }

    function setImplementation(address _implementation) public onlyOwner {
        implementation = _implementation;
    }

    function create() external onlyOwner {
        address proxy = address(new AonProxy(implementation));
        emit AonCreated(proxy);
    }
}
