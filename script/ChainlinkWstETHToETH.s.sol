// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { ChainlinkWstETHToETH, IWstETH } from "src/oracles/contracts/ChainlinkWstETHToETH.sol";

contract DeployDahlia is BaseScript {
    bytes32 private constant _SALT = keccak256(abi.encode("ChainlinkWstETHToETH_V1"));

    function run() public {
        address wstEth = _envAddress("WSTETH");
        address stEthToEthFeed = _envAddress("STETH_ETH_FEED");
        uint256 value = IWstETH(wstEth).stEthPerToken();
        vm.assertGt(value, 0, "Invalid WSTETH Contract");
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(stEthToEthFeed).latestRoundData();
        vm.assertGt(answer, 0, "Invalid answer STETH_ETH_FEED");
        vm.assertGt(updatedAt, 0, "Invalid updatedAt STETH_ETH_FEED");
        ChainlinkWstETHToETH.Params memory params = ChainlinkWstETHToETH.Params({ wstEth: wstEth, stEthToEthFeed: stEthToEthFeed });

        bytes memory encodedArgs = abi.encode(params);
        bytes memory initCode = abi.encodePacked(type(ChainlinkWstETHToETH).creationCode, encodedArgs);
        string memory name = type(ChainlinkWstETHToETH).name;
        _deploy(name, DEPLOYED_CHAINLINK_WSTETH_ETH, _SALT, initCode);
    }
}
