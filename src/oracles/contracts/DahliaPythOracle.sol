// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";

import { DahliaOracleStaticAddress } from "src/oracles/abstracts/DahliaOracleStaticAddress.sol";
import { IDahliaOracle } from "src/oracles/interfaces/IDahliaOracle.sol";

/// @title DahliaPythOracle
/// @notice A contract for fetching price from Pyth Oracle
contract DahliaPythOracle is Ownable2Step, IDahliaOracle, DahliaOracleStaticAddress {
    using SafeCastLib for *;
    using FixedPointMathLib for uint256;

    /// @notice Emitted when the contract is deployed
    /// @param params Initial parameters
    event ParamsUpdated(Params params);

    /// @notice Emitted when the max oracle delay is updated
    /// @param oldMaxDelays The previous max oracle delay settings
    /// @param newMaxDelays The new max oracle delay settings
    event MaximumOracleDelaysUpdated(Delays oldMaxDelays, Delays newMaxDelays);

    uint256 public immutable ORACLE_PRECISION;

    address public immutable BASE_TOKEN; // 20 bytes
    address public immutable QUOTE_TOKEN; // 20 bytes
    bytes32 public immutable BASE_FEED; // 32 bytes
    bytes32 public immutable QUOTE_FEED; // 32 bytes
    uint256 public baseMaxDelay; // 32 bytes
    uint256 public quoteMaxDelay; // 32 bytes

    struct Params {
        address baseToken;
        bytes32 baseFeed;
        address quoteToken;
        bytes32 quoteFeed;
    }

    /// @notice Struct to hold max delay settings
    struct Delays {
        uint256 baseMaxDelay;
        uint256 quoteMaxDelay;
    }

    /// @notice Initializes the contract with owner, oracle parameters, and Pyth static oracle address
    /// @param owner The address of the contract owner
    /// @param params The pyth oracle parameters
    /// @param staticOracleAddress The address of the Pyth static oracle
    constructor(address owner, Params memory params, Delays memory delays, address staticOracleAddress)
        Ownable(owner)
        DahliaOracleStaticAddress(staticOracleAddress)
    {
        BASE_TOKEN = params.baseToken;
        BASE_FEED = params.baseFeed;
        QUOTE_TOKEN = params.quoteToken;
        QUOTE_FEED = params.quoteFeed;

        emit ParamsUpdated(params);
        _setMaximumOracleDelays(delays);

        int32 baseTokenDecimals = getDecimals(params.baseToken); // 95434 354543 * 10^-8
        int32 quoteTokenDecimals = getDecimals(params.quoteToken);
        uint256 precision = (36 + quoteTokenDecimals + getFeedDecimals(params.baseFeed) - getFeedDecimals(params.quoteFeed) - baseTokenDecimals).toUint256();

        ORACLE_PRECISION = 10 ** precision;
    }

    function getDecimals(address token) internal view returns (int32) {
        return (IERC20Metadata(token).decimals()).toInt32();
    }

    function getFeedDecimals(bytes32 feedId) internal view returns (int32) {
        return IPyth(_STATIC_ORACLE_ADDRESS).getPriceUnsafe(feedId).expo;
    }

    /// @inheritdoc IDahliaOracle
    function getPrice() external view returns (uint256 price, bool isBadData) {
        PythStructs.Price memory basePrice = IPyth(_STATIC_ORACLE_ADDRESS).getPriceNoOlderThan(BASE_FEED, baseMaxDelay);
        PythStructs.Price memory quotePrice = IPyth(_STATIC_ORACLE_ADDRESS).getPriceNoOlderThan(QUOTE_FEED, quoteMaxDelay);

        price = ORACLE_PRECISION.mulDiv(basePrice.price.toUint256(), quotePrice.price.toUint256());
        isBadData = price == 0;
    }

    /// @dev Internal function to update max oracle delays
    function _setMaximumOracleDelays(Delays memory delays) internal {
        emit MaximumOracleDelaysUpdated({ oldMaxDelays: Delays({ baseMaxDelay: baseMaxDelay, quoteMaxDelay: quoteMaxDelay }), newMaxDelays: delays });
        baseMaxDelay = delays.baseMaxDelay;
        quoteMaxDelay = delays.quoteMaxDelay;
    }

    /// @notice Set new max oracle delays
    /// @param delays The new max delay settings
    function setMaximumOracleDelays(Delays memory delays) external onlyOwner {
        _setMaximumOracleDelays(delays);
    }
}
