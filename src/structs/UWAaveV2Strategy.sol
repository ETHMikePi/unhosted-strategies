// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/// @notice represents an asset and an amount, the asset can be either a token or a special constant.
struct Asset {
    address asset;
    uint256 amount;
}
