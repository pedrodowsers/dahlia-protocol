// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

// Inspired by OpenZeppelin's Timelock.sol
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/mocks/compound/CompTimelock.sol

/// @title Timelock Contract
/// @notice A contract for managing time-delayed transactions with ownership control
contract Timelock is Ownable2Step {
    /// @notice Delay is below the minimum allowed.
    error DelayMustExceedMinimumDelay();
    /// @notice Delay is above the maximum allowed.
    error DelayMustNotExceedMaximumDelay();
    /// @notice A call is not from the Timelock contract.
    error CallMustComeFromTimelock();
    /// @notice The execution block doesn't meet the delay requirement.
    error EstimatedExecutionBlockMustSatisfyDelay();
    /// @notice A transaction hasn't been queued.
    error TransactionHasNotBeenQueued();
    /// @notice A transaction hasn't passed the timelock period.
    error TransactionHasNotSurpassedTimeLock();
    /// @notice A transaction is too old to execute.
    error TransactionIsStale();
    /// @notice Transaction execution fails.
    error TransactionExecutionReverted();

    /// @notice Emitted when a new delay is set.
    event NewDelay(uint256 indexed newDelay);
    /// @notice Emitted when a transaction is canceled.
    event CancelTransaction(bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta);
    /// @notice Emitted when a transaction is executed.
    event ExecuteTransaction(bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta);
    /// @notice Emitted when a transaction is queued.
    event QueueTransaction(bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta);

    uint256 public constant GRACE_PERIOD = 14 days; // Time after eta during which a transaction can be executed
    uint256 public constant MINIMUM_DELAY = 1 days; // Minimum delay for a transaction
    uint256 public constant MAXIMUM_DELAY = 30 days; // Maximum delay for a transaction

    uint256 public delay; // Current delay for transactions

    mapping(bytes32 => bool) public queuedTransactions; // Tracks queued transactions

    constructor(address admin_, uint256 delay_) Ownable(admin_) {
        _setDelay(delay_);
    }

    /// @notice Internal function to set the delay, ensuring it's within bounds.
    function _setDelay(uint256 delay_) internal {
        require(delay_ >= MINIMUM_DELAY, DelayMustExceedMinimumDelay());
        require(delay_ <= MAXIMUM_DELAY, DelayMustNotExceedMaximumDelay());

        delay = delay_;
        emit NewDelay(delay);
    }

    /// @notice Public function to set the delay, callable only by the contract itself.
    function setDelay(uint256 delay_) public {
        require(msg.sender == address(this), CallMustComeFromTimelock());

        _setDelay(delay_);
    }

    /// @notice Queues a transaction to be executed after the delay.
    function queueTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) public onlyOwner returns (bytes32) {
        require(_getBlockTimestamp() + delay < eta, EstimatedExecutionBlockMustSatisfyDelay());

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    /// @notice Cancels a queued transaction.
    function cancelTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta) public onlyOwner {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    /// @notice Executes a queued transaction if conditions are met.
    function executeTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta)
        public
        payable
        onlyOwner
        returns (bytes memory)
    {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], TransactionHasNotBeenQueued());
        require(_getBlockTimestamp() >= eta, TransactionHasNotSurpassedTimeLock());
        require(_getBlockTimestamp() <= eta + GRACE_PERIOD, TransactionIsStale());

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // Execute the call
        (bool success, bytes memory returnData) = target.call{ value: value }(callData);
        require(success, TransactionExecutionReverted());

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }

    /// @notice Returns the current block timestamp.
    function _getBlockTimestamp() private view returns (uint256) {
        return block.timestamp;
    }
}
