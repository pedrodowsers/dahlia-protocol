// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title Errors library
library Errors {
    /// @notice Thrown when a negative value is encountered.
    error NegativeAnswer(int256 value);

    /// @notice Thrown when a Uniswap pair is not supported.
    error PairNotSupported(address baseToken, address quoteToken);

    /// @notice Thrown when a zero address is provided.
    error ZeroAddress();
}
