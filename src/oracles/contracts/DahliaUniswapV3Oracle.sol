// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IStaticOracle } from "@uniswap-v3-oracle/solidity/interfaces/IStaticOracle.sol";

import { DahliaOracleStaticAddress } from "src/oracles/abstracts/DahliaOracleStaticAddress.sol";
import { Errors } from "src/oracles/helpers/Errors.sol";
import { IDahliaOracle } from "src/oracles/interfaces/IDahliaOracle.sol";

/// @title DahliaUniswapV3Oracle
/// @notice A contract for fetching TWAP from Uniswap V3
contract DahliaUniswapV3Oracle is Ownable2Step, IDahliaOracle, ERC165, DahliaOracleStaticAddress {
    /// @dev Parameters for the oracle setup
    struct Params {
        address uniswapV3PairAddress; // Address of the Uniswap V3 pair
        address baseToken; // Base token address
        address quoteToken; // Quote token address
    }

    /// @dev Emitted when the TWAP duration is updated
    event TwapDurationUpdated(uint256 oldTwapDuration, uint256 newTwapDuration);

    /// @notice Emitted when the contract is deployed
    /// @param params Initial parameters
    event ParamsUpdated(Params params);

    error TwapDurationIsTooShort();

    uint32 public constant MIN_TWAP_DURATION = 300;

    /// @notice Address of the Uniswap V3 pair
    address public immutable UNI_V3_PAIR_ADDRESS;

    /// @notice Precision used for TWAP calculations
    uint128 public constant TWAP_PRECISION = 1e36;

    /// @notice Base token used in the TWAP
    address public immutable UNISWAP_V3_TWAP_BASE_TOKEN;

    /// @notice Quote token used in the TWAP
    address public immutable UNISWAP_V3_TWAP_QUOTE_TOKEN;

    /// @notice Duration for the TWAP calculation
    uint32 public twapDuration;

    /// @dev Constructor to initialize the oracle parameters
    /// @param params Struct containing oracle parameters
    /// @param uniswapStaticOracle Address of the static oracle
    /// @param duration The TWAP duration
    constructor(address owner, Params memory params, address uniswapStaticOracle, uint32 duration)
        Ownable(owner)
        DahliaOracleStaticAddress(uniswapStaticOracle)
    {
        UNI_V3_PAIR_ADDRESS = params.uniswapV3PairAddress;
        UNISWAP_V3_TWAP_BASE_TOKEN = params.baseToken;
        UNISWAP_V3_TWAP_QUOTE_TOKEN = params.quoteToken;
        _setTwapDuration(duration);
        emit ParamsUpdated(params);

        bool pairSupported = IStaticOracle(_STATIC_ORACLE_ADDRESS).isPairSupported(UNISWAP_V3_TWAP_BASE_TOKEN, UNISWAP_V3_TWAP_QUOTE_TOKEN);

        if (!pairSupported) revert Errors.PairNotSupported(UNISWAP_V3_TWAP_BASE_TOKEN, UNISWAP_V3_TWAP_QUOTE_TOKEN);
    }

    /// @dev Internal function to update the TWAP duration
    /// @param newTwapDuration The new TWAP duration
    function _setTwapDuration(uint32 newTwapDuration) internal {
        require(newTwapDuration >= MIN_TWAP_DURATION, TwapDurationIsTooShort());
        emit TwapDurationUpdated({ oldTwapDuration: twapDuration, newTwapDuration: newTwapDuration });
        twapDuration = newTwapDuration;
    }

    /// @notice Set a new TWAP duration for the Uniswap V3 TWAP oracle
    /// @dev Only callable by the timelock address
    /// @param newTwapDuration The new TWAP duration in seconds
    function setTwapDuration(uint32 newTwapDuration) external onlyOwner {
        _setTwapDuration(newTwapDuration);
    }

    /// @dev Internal function to get the TWAP price from Uniswap V3
    /// @return price The calculated TWAP price
    function _getUniswapV3Twap() internal view returns (uint256 price) {
        address[] memory pools = new address[](1);
        pools[0] = UNI_V3_PAIR_ADDRESS;

        price = IStaticOracle(_STATIC_ORACLE_ADDRESS).quoteSpecificPoolsWithTimePeriod({
            baseAmount: TWAP_PRECISION,
            baseToken: UNISWAP_V3_TWAP_BASE_TOKEN,
            quoteToken: UNISWAP_V3_TWAP_QUOTE_TOKEN,
            pools: pools,
            period: twapDuration
        });
    }
    /// @inheritdoc IDahliaOracle

    function getPrice() external view returns (uint256 price, bool isBadData) {
        price = _getUniswapV3Twap();
        isBadData = false;
    }
}
