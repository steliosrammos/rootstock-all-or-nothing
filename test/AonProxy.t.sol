// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/AonProxy.sol";

// Dummy implementation contract used for testing delegate calls through the proxy
contract DummyImpl {
    uint256 public value;

    function setValue(uint256 _v) external {
        value = _v;
    }
}

contract AonProxyTest is Test {
    AonProxy internal proxy;
    DummyImpl internal impl;

    function setUp() public {
        impl = new DummyImpl();
        proxy = new AonProxy(address(impl));
    }

    function test_ImplementationAddressIsStored() public view {
        assertEq(proxy.implementation(), address(impl));
    }

    function test_DelegateCallUpdatesProxyStorage() public {
        DummyImpl proxyAsImpl = DummyImpl(address(proxy));

        proxyAsImpl.setValue(123);

        assertEq(proxyAsImpl.value(), 123);
        assertEq(impl.value(), 0);
    }
}
