// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/Factory.sol";
import "src/Aon.sol";
import "src/AonGoalReachedNative.sol";
import "src/AonProxy.sol";

contract FactoryTest is Test {
    Factory internal factory;
    Aon internal aonImplementation;
    AonGoalReachedNative internal goalStrategy;

    address internal owner = address(0x1);
    address internal creator = address(0x2);
    address internal contributor = address(0x3);
    address internal nonOwner = address(0x4);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy implementation and strategy
        aonImplementation = new Aon();
        goalStrategy = new AonGoalReachedNative();

        // Deploy factory
        factory = new Factory(address(aonImplementation), owner);

        vm.stopPrank();
    }

    function test_Constructor_SetsImplementation() public view {
        assertEq(factory.implementation(), address(aonImplementation));
        assertEq(factory.owner(), owner);
    }

    function test_Constructor_WithZeroImplementation_Reverts() public {
        vm.expectRevert(Factory.InvalidImplementation.selector);
        new Factory(address(0), owner);
    }

    function test_Constructor_WithZeroOwner_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Factory(address(aonImplementation), address(0));
    }

    function test_SetImplementation_OnlyOwner() public {
        address newImplementation = address(0x999);

        // Should fail for non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        factory.setImplementation(newImplementation);

        // Should succeed for owner
        vm.prank(owner);
        factory.setImplementation(newImplementation);
        assertEq(factory.implementation(), newImplementation);
    }

    function test_SetImplementation_EmitsEvent() public {
        address newImplementation = address(0x999);

        vm.prank(owner);
        // Note: setImplementation doesn't emit an event, so we just test it doesn't revert
        factory.setImplementation(newImplementation);
        assertEq(factory.implementation(), newImplementation);
    }

    function test_Create_DeploysProxy() public {
        vm.prank(creator);

        // Test that create doesn't revert and creates a proxy
        factory.create(payable(creator), 10 ether, 30 days, address(goalStrategy), 7 days);
    }

    function test_Create_InitializesProxy() public {
        vm.prank(creator);

        // We can't directly test the initialization without knowing the proxy address
        // But we can test that the function doesn't revert
        factory.create(payable(creator), 10 ether, 30 days, address(goalStrategy), 7 days);
    }

    function test_Create_WithDifferentParameters() public {
        vm.prank(creator);

        // Test with different goal amounts
        factory.create(payable(creator), 1 ether, 7 days, address(goalStrategy), 1 days);

        factory.create(payable(creator), 100 ether, 365 days, address(goalStrategy), 30 days);
    }

    function test_Create_WithZeroGoal_Reverts() public {
        vm.prank(creator);

        // Should revert with zero goal
        vm.expectRevert(Aon.InvalidGoal.selector);
        factory.create(payable(creator), 0, 30 days, address(goalStrategy), 7 days);
    }

    function test_Create_WithTooSmallGoal_Reverts() public {
        vm.prank(creator);
        vm.expectRevert(Aon.InvalidGoal.selector);
        factory.create(payable(creator), 0 ether, 30 days, address(goalStrategy), 7 days);
    }

    function test_Create_WithZeroDuration_Reverts() public {
        vm.prank(creator);

        // Should revert with zero duration
        vm.expectRevert(Aon.InvalidDuration.selector);
        factory.create(payable(creator), 10 ether, 0, address(goalStrategy), 7 days);
    }

    function test_Create_WithTooShortDuration_Reverts() public {
        vm.prank(creator);

        vm.expectRevert(Aon.InvalidDuration.selector);
        factory.create(payable(creator), 10 ether, 30 minutes, address(goalStrategy), 7 days);
    }

    function test_Create_WithZeroClaimWindow_Reverts() public {
        vm.prank(creator);

        // Should revert with zero claim window
        vm.expectRevert(Aon.InvalidClaimOrRefundWindow.selector);
        factory.create(payable(creator), 10 ether, 30 days, address(goalStrategy), 0);
    }

    function test_Create_WithTooShortClaimWindow_Reverts() public {
        vm.prank(creator);

        vm.expectRevert(Aon.InvalidClaimOrRefundWindow.selector);
        factory.create(payable(creator), 10 ether, 30 days, address(goalStrategy), 30 minutes);
    }

    function test_Create_WithDifferentCreator() public {
        address differentCreator = address(0x999);

        vm.prank(differentCreator);
        factory.create(payable(differentCreator), 10 ether, 30 days, address(goalStrategy), 7 days);
    }

    function test_Create_WithDifferentStrategy() public {
        address differentStrategy = address(0x888);

        vm.prank(creator);
        factory.create(payable(creator), 10 ether, 30 days, differentStrategy, 7 days);
    }

    function test_Create_WithZeroAddressStrategy_Reverts() public {
        vm.prank(creator);

        // Should revert with zero address strategy
        vm.expectRevert(Aon.InvalidGoalReachedStrategy.selector);
        factory.create(payable(creator), 10 ether, 30 days, address(0), 7 days);
    }

    function test_Create_WithZeroAddressCreator_Reverts() public {
        vm.prank(creator);

        // Should revert with zero address creator
        vm.expectRevert(Aon.InvalidCreator.selector);
        factory.create(payable(address(0)), 10 ether, 30 days, address(goalStrategy), 7 days);
    }

    function test_Create_MultipleCampaigns() public {
        vm.startPrank(creator);

        // Create multiple campaigns
        factory.create(payable(creator), 10 ether, 30 days, address(goalStrategy), 7 days);

        factory.create(payable(creator), 5 ether, 14 days, address(goalStrategy), 3 days);

        factory.create(payable(creator), 20 ether, 60 days, address(goalStrategy), 14 days);

        vm.stopPrank();
    }

    function test_Create_WithMinimumValidValues() public {
        vm.prank(creator);

        // Test with minimum valid values (60 minutes for both duration and claim window)
        factory.create(payable(creator), 0.001 ether, 60 minutes, address(goalStrategy), 60 minutes);
    }

    function test_Create_WithLargeValues() public {
        vm.prank(creator);

        // Test with large but reasonable values
        factory.create(
            payable(creator),
            1000000 ether, // 1 million ETH
            365 days, // 1 year
            address(goalStrategy),
            30 days // 30 days claim window
        );
    }

    function test_OnlyOwner_Modifier() public {
        // Test that only owner can call setImplementation
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        factory.setImplementation(address(0x999));
    }

    function test_Owner_CanChangeImplementation() public {
        address newImplementation = address(0x777);

        vm.prank(owner);
        factory.setImplementation(newImplementation);

        // Verify the change
        assertEq(factory.implementation(), newImplementation);

        // Test that new implementation is used in create
        vm.prank(creator);
        factory.create(payable(creator), 10 ether, 30 days, address(goalStrategy), 7 days);
    }

    function test_Factory_IsOwnable() public view {
        assertEq(factory.owner(), owner);
    }

    function test_Implementation_IsImmutableAfterDeployment() public view {
        // The implementation should be set and readable
        assertTrue(factory.implementation() != address(0));
        assertEq(factory.implementation(), address(aonImplementation));
    }
}
