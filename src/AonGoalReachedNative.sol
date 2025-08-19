// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IAonGoalReached {
    function isGoalReached() external view returns (bool);
}

interface IAon {
    function goal() external view returns (uint256);
}

contract AonGoalReachedNative is IAonGoalReached {
    function isGoalReached() external view returns (bool) {
        IAon aonContract = IAon(address(this));
        uint256 goal = aonContract.goal();
        return msg.sender.balance >= goal;
    }
}
