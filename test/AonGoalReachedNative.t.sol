// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/AonGoalReachedNative.sol";
import "./Aon/AonTestBase.sol";

/// @notice Mock Aon contract for testing AonGoalReachedNative in isolation
contract MockAon is IAon {
    uint256 public override goalBalance;
    uint256 public override goal;
    IAonGoalReached public goalReachedStrategy;

    constructor(uint256 _goalBalance, uint256 _goal, address _goalReachedStrategy) {
        goalBalance = _goalBalance;
        goal = _goal;
        goalReachedStrategy = IAonGoalReached(_goalReachedStrategy);
    }

    function setGoalBalance(uint256 _goalBalance) external {
        goalBalance = _goalBalance;
    }

    function setGoal(uint256 _goal) external {
        goal = _goal;
    }

    /// @notice Calls the goal reached strategy from this contract's context
    /// @dev This allows testing AonGoalReachedNative with msg.sender = MockAon
    function checkGoalReached() external view returns (bool) {
        return goalReachedStrategy.isGoalReached();
    }
}

    contract AonGoalReachedNativeTest is Test {
        AonGoalReachedNative public goalReachedStrategy;

        function setUp() public {
            goalReachedStrategy = new AonGoalReachedNative();
        }

        /*
         * ISOLATED TESTS WITH MOCK AON CONTRACT
         */

        function test_IsGoalReached_ReturnsFalse_WhenBalanceLessThanGoal() public {
            MockAon mockAon = new MockAon(5 ether, 10 ether, address(goalReachedStrategy));
            assertFalse(mockAon.checkGoalReached(), "Should return false when balance < goal");
        }

        function test_IsGoalReached_ReturnsTrue_WhenBalanceGreaterOrEqualGoal() public {
            // Test balance == goal
            MockAon mockAon1 = new MockAon(10 ether, 10 ether, address(goalReachedStrategy));
            assertTrue(mockAon1.checkGoalReached(), "Should return true when balance == goal");

            // Test balance > goal
            MockAon mockAon2 = new MockAon(15 ether, 10 ether, address(goalReachedStrategy));
            assertTrue(mockAon2.checkGoalReached(), "Should return true when balance > goal");
        }

        function test_IsGoalReached_EdgeCases() public {
            // Zero balance, non-zero goal
            MockAon mockAon1 = new MockAon(0, 10 ether, address(goalReachedStrategy));
            assertFalse(mockAon1.checkGoalReached(), "Should return false when balance is zero");

            // Non-zero balance, zero goal
            MockAon mockAon2 = new MockAon(5 ether, 0, address(goalReachedStrategy));
            assertTrue(mockAon2.checkGoalReached(), "Should return true when goal is zero");

            // Both zero
            MockAon mockAon3 = new MockAon(0, 0, address(goalReachedStrategy));
            assertTrue(mockAon3.checkGoalReached(), "Should return true when both are zero (0 >= 0)");

            // Large values
            MockAon mockAon4 = new MockAon(type(uint256).max / 2, type(uint256).max, address(goalReachedStrategy));
            assertFalse(mockAon4.checkGoalReached(), "Should handle large values correctly");
        }

        /*
         * INTEGRATION TESTS WITH REAL AON CONTRACT
         * These tests verify the strategy works correctly when used by the Aon contract
         */

        function test_IsGoalReached_Integration_WithRealAon() public {
            ConcreteAonTestBase testBase = new ConcreteAonTestBase();
            testBase.setUp();

            // Test goal not reached
            vm.prank(testBase.contributor1());
            testBase.aon().contribute{value: 5 ether}(0, 0);
            Aon.Status status1 = testBase.aon().getStatus();
            assertEq(uint8(status1), uint8(Aon.Status.Active), "Status should be Active when goal not reached");

            // Test goal reached
            vm.prank(testBase.contributor1());
            testBase.aon().contribute{value: 5 ether}(0, 0); // Total: 10 ether = goal
            Aon.Status status2 = testBase.aon().getStatus();
            assertEq(uint8(status2), uint8(Aon.Status.Successful), "Status should be Successful when goal reached");
        }

        function test_IsGoalReached_Integration_WithContributorFees() public {
            ConcreteAonTestBase testBase = new ConcreteAonTestBase();
            testBase.setUp();

            // Contribute with fees - goalBalance excludes contributor fees
            vm.prank(testBase.contributor1());
            testBase.aon().contribute{value: 10.1 ether}(0, 0.1 ether);

            // goalBalance = 10.1 - 0.1 = 10 ether, which equals goal
            Aon.Status status = testBase.aon().getStatus();
            assertEq(uint8(status), uint8(Aon.Status.Successful), "Status should be Successful");
            assertEq(testBase.aon().goalBalance(), 10 ether, "Goal balance should exclude contributor fees");
        }
    }

    /// @notice Concrete implementation of AonTestBase for integration tests
    contract ConcreteAonTestBase is AonTestBase {}
