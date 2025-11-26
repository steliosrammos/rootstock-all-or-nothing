// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "openzeppelin-contracts/contracts/proxy/Proxy.sol";
contract AonProxy is Proxy {
    address public immutable implementation;

    error DirectTransfersNotAllowed();
    error InvalidImplementation();

    constructor(address impl) Proxy() {
        if (impl == address(0)) revert InvalidImplementation();
        implementation = impl;
    }

    function _implementation() internal view override returns (address) {
        return implementation;
    }

    // slither-disable-next-line locked-ether
    receive() external payable {
        revert DirectTransfersNotAllowed();
    }
}
