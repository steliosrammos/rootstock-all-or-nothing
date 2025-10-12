// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IAonGoalReached {
    function isGoalReached() external view returns (bool);
}

interface IAon {
    function goal() external view returns (uint256);
    function goalBalance() external view returns (uint256);
}

contract AonGoalReachedNative is IAonGoalReached {
    function isGoalReached() external view returns (bool) {
        IAon aonContract = IAon(msg.sender);
        return aonContract.goalBalance() >= aonContract.goal();
    }
}
