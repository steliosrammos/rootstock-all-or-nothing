// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IAonGoalReached {
    function isGoalReached() external view returns (bool);
}

interface IAon {
    function goalBalance() external view returns (uint256);
    function goal() external view returns (uint256);
}

contract AonGoalReachedNative is IAonGoalReached {
    function isGoalReached() external view returns (bool) {
        uint256 goalBalance = IAon(msg.sender).goalBalance();
        uint256 targetGoal = IAon(msg.sender).goal();
        return goalBalance >= targetGoal;
    }
}
