// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/Aon.sol";
import "../src/AonGoalReachedNative.sol";
import "../src/Factory.sol";
import "../src/AonProxy.sol";

contract Deploy is Script {
    function run() external returns (Factory, AonGoalReachedNative) {
        uint256 deployerPrivateKey = vm.envUint("RSK_DEPLOYMENT_PRIVATE_KEY");

        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Aon logic contract
        Aon aonImplementation = new Aon();

        // 2. Deploy the goal-reached strategy contract
        AonGoalReachedNative goalReachedStrategy = new AonGoalReachedNative();

        // 3. Deploy the Factory, linking it to the Aon logic contract
        Factory factory = new Factory(address(aonImplementation));

        vm.stopBroadcast();

        console.log("--------------------");
        console.log("Deployment Summary");
        console.log("--------------------");
        console.log("Deployer Address:", deployerAddress);
        console.log("Aon Implementation:", address(aonImplementation));
        console.log("Goal Reached Strategy:", address(goalReachedStrategy));
        console.log("Factory:", address(factory));
        console.log("--------------------");

        return (factory, goalReachedStrategy);
    }
}
