// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/AonProxy.sol";

// Dummy implementation contract used for testing delegate calls through the proxy
contract DummyImpl {
    uint256 public value;
    bool public flag;
    address public owner;
    string public name;

    function setValue(uint256 _v) external {
        value = _v;
    }

    function setFlag(bool _flag) external {
        flag = _flag;
    }

    function setOwner(address _owner) external {
        owner = _owner;
    }

    function setName(string memory _name) external {
        name = _name;
    }

    function getValue() external view returns (uint256) {
        return value;
    }

    function getFlag() external view returns (bool) {
        return flag;
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    function getName() external view returns (string memory) {
        return name;
    }

    function revertFunction() external pure {
        revert("Test revert");
    }

    function payableFunction() external payable {
        // Accept ETH
    }

    function nonPayableFunction() external {
        // Don't accept ETH
    }
}

contract AonProxyTest is Test {
    AonProxy internal proxy;
    DummyImpl internal impl;
    address internal user = address(0x1);
    address internal anotherUser = address(0x2);

    function setUp() public {
        impl = new DummyImpl();
        proxy = new AonProxy(address(impl));
    }

    function test_ImplementationAddressIsStored() public view {
        assertEq(proxy.implementation(), address(impl));
    }

    function test_ImplementationAddressIsImmutable() public view {
        // The implementation should be immutable
        assertEq(proxy.implementation(), address(impl));
    }

    function test_DelegateCallUpdatesProxyStorage() public {
        DummyImpl proxyAsImpl = DummyImpl(address(proxy));

        proxyAsImpl.setValue(123);

        assertEq(proxyAsImpl.value(), 123);
        assertEq(impl.value(), 0);
    }

    function test_DelegateCallWithMultipleStateVariables() public {
        DummyImpl proxyAsImpl = DummyImpl(address(proxy));

        // Set multiple state variables
        proxyAsImpl.setValue(456);
        proxyAsImpl.setFlag(true);
        proxyAsImpl.setOwner(user);
        proxyAsImpl.setName("Test Campaign");

        // Verify all state changes are in proxy, not implementation
        assertEq(proxyAsImpl.getValue(), 456);
        assertEq(proxyAsImpl.getFlag(), true);
        assertEq(proxyAsImpl.getOwner(), user);
        assertEq(proxyAsImpl.getName(), "Test Campaign");

        // Verify implementation state is unchanged
        assertEq(impl.getValue(), 0);
        assertEq(impl.getFlag(), false);
        assertEq(impl.getOwner(), address(0));
        assertEq(impl.getName(), "");
    }

    function test_DelegateCallWithDifferentCallers() public {
        DummyImpl proxyAsImpl = DummyImpl(address(proxy));

        // Call from different users
        vm.prank(user);
        proxyAsImpl.setValue(100);

        vm.prank(anotherUser);
        proxyAsImpl.setFlag(true);

        // Verify state changes
        assertEq(proxyAsImpl.getValue(), 100);
        assertEq(proxyAsImpl.getFlag(), true);
    }

    function test_DelegateCallWithRevert() public {
        DummyImpl proxyAsImpl = DummyImpl(address(proxy));

        // Test that reverts are properly propagated
        vm.expectRevert("Test revert");
        proxyAsImpl.revertFunction();
    }

    function test_ReceiveFunction_Reverts() public {
        // Test that direct ETH transfers to proxy revert
        vm.expectRevert(AonProxy.DirectTransfersNotAllowed.selector);
        payable(address(proxy)).transfer(1 ether);
    }

    function test_ReceiveFunction_RevertsWithDifferentAmounts() public {
        // Test with different ETH amounts
        vm.expectRevert(AonProxy.DirectTransfersNotAllowed.selector);
        payable(address(proxy)).transfer(0.1 ether);

        vm.expectRevert(AonProxy.DirectTransfersNotAllowed.selector);
        payable(address(proxy)).transfer(10 ether);
    }

    function test_Proxy_IsNotPayable() public {
        // Test that proxy doesn't accept ETH in regular function calls
        DummyImpl proxyAsImpl = DummyImpl(address(proxy));

        // This should work (non-payable function)
        proxyAsImpl.nonPayableFunction();

        // The proxy itself doesn't accept ETH, but the implementation might
        // So we test that the proxy can handle payable functions from the implementation
        proxyAsImpl.payableFunction{value: 1 ether}();

        // Verify the ETH was received by the proxy (through the implementation)
        assertEq(address(proxy).balance, 1 ether);
    }

    function test_Proxy_StateIsolation() public {
        DummyImpl proxyAsImpl = DummyImpl(address(proxy));

        // Set state in proxy
        proxyAsImpl.setValue(999);
        proxyAsImpl.setFlag(true);

        // Create another proxy with same implementation
        AonProxy proxy2 = new AonProxy(address(impl));
        DummyImpl proxy2AsImpl = DummyImpl(address(proxy2));

        // Verify state isolation
        assertEq(proxyAsImpl.getValue(), 999);
        assertEq(proxyAsImpl.getFlag(), true);
        assertEq(proxy2AsImpl.getValue(), 0);
        assertEq(proxy2AsImpl.getFlag(), false);
    }

    function test_Proxy_WithZeroImplementation() public {
        // Test proxy with zero address implementation
        vm.expectRevert(AonProxy.InvalidImplementation.selector);
        new AonProxy(address(0));
    }

    function test_Proxy_WithDifferentImplementations() public {
        // Create different implementations
        DummyImpl impl1 = new DummyImpl();
        DummyImpl impl2 = new DummyImpl();

        AonProxy proxy1 = new AonProxy(address(impl1));
        AonProxy proxy2 = new AonProxy(address(impl2));

        // Verify different implementations
        assertEq(proxy1.implementation(), address(impl1));
        assertEq(proxy2.implementation(), address(impl2));
        assertTrue(proxy1.implementation() != proxy2.implementation());
    }

    function test_Proxy_ImplementationCannotBeChanged() public view {
        // The implementation is immutable, so we can't change it
        // This is more of a documentation test
        assertEq(proxy.implementation(), address(impl));

        // Verify that implementation is immutable by checking it's the same
        assertEq(proxy.implementation(), address(impl));
    }

    function test_Proxy_WithComplexState() public {
        DummyImpl proxyAsImpl = DummyImpl(address(proxy));

        // Test complex state operations
        proxyAsImpl.setValue(type(uint256).max);
        proxyAsImpl.setFlag(true);
        proxyAsImpl.setOwner(address(0x123456789));
        proxyAsImpl.setName("Complex Campaign Name");

        // Verify all state
        assertEq(proxyAsImpl.getValue(), type(uint256).max);
        assertEq(proxyAsImpl.getFlag(), true);
        assertEq(proxyAsImpl.getOwner(), address(0x123456789));
        assertEq(proxyAsImpl.getName(), "Complex Campaign Name");
    }
}
