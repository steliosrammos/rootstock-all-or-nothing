// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IAonGoalReached {
    function isGoalReached() external view returns (bool);
}

interface IAon {
    // This function imho absolutely pointless and will come to haunt you in case you ever want to do more sophisticated goals
    function getGoalInfo() external view returns (uint256 goalBalance, uint256 targetGoal);
}

contract AonGoalReachedNative is IAonGoalReached {
    function isGoalReached() external view returns (bool) {
        (uint256 goalBalance, uint256 targetGoal) = IAon(msg.sender).getGoalInfo();
        return goalBalance >= targetGoal;
    }
}
