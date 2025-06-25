// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/proxy/Proxy.sol";

contract AonProxy is Proxy {
    address public immutable implementation;

    constructor(address impl) Proxy() {
        implementation = impl;
    }

    function _implementation() internal view override returns (address) {
        return implementation;
    }
}
