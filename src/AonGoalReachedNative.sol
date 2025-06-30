// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IAonGoalReached {
    function isGoalReached() external view returns (bool);
}

interface IAonForGoalCheck {
    function goal() external view returns (uint256);
}

contract AonGoalReachedNative is IAonGoalReached {
    function isGoalReached() external view returns (bool) {
        IAonForGoalCheck aon = IAonForGoalCheck(msg.sender);
        return msg.sender.balance >= aon.goal();
    }
}
