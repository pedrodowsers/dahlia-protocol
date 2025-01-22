// SPDX-License-Identifier: MIT
pragma solidity >=0.8.27;

import { Script } from "@forge-std/Script.sol";
import { console } from "@forge-std/console.sol";
import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { LibString } from "@solady/utils/LibString.sol";

abstract contract BaseScript is Script {
    using LibString for *;

    address internal deployer;
    string internal scannerBaseUrl;

    string internal constant DEPLOYED_REGISTRY = "DEPLOYED_REGISTRY";
    string internal constant DEPLOYED_DAHLIA = "DEPLOYED_DAHLIA";
    string internal constant DEPLOYED_PYTH_ORACLE_FACTORY = "DEPLOYED_PYTH_ORACLE_FACTORY";
    string internal constant DEPLOYED_WRAPPED_VAULT_FACTORY = "DEPLOYED_WRAPPED_VAULT_FACTORY";
    string internal constant DEPLOYED_WRAPPED_VAULT_IMPLEMENTATION = "DEPLOYED_WRAPPED_VAULT_IMPLEMENTATION";
    string internal constant DEPLOYED_IRM_FACTORY = "DEPLOYED_IRM_FACTORY";
    string internal constant DEPLOYED_TIMELOCK = "DEPLOYED_TIMELOCK";
    string internal constant DEPLOYED_CHAINLINK_WSTETH_ETH = "DEPLOYED_CHAINLINK_WSTETH_ETH";

    string internal constant DAHLIA_OWNER = "DAHLIA_OWNER";
    string internal constant INDEX = "INDEX";
    string internal constant POINTS_FACTORY = "POINTS_FACTORY";
    string internal constant TIMELOCK_DELAY = "TIMELOCK_DELAY";

    function setUp() public virtual {
        deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        scannerBaseUrl = _envString("SCANNER_BASE_URL");
        console.log("Deployer address:", deployer);
    }

    function _printContract(string memory name, address addr) internal view {
        string memory host = string(abi.encodePacked(scannerBaseUrl, "/"));
        string memory addressUrl = string(abi.encodePacked(host, "address/", (addr).toHexString()));
        string memory env = string(abi.encodePacked(name, "=", (addr).toHexString()));
        console.log(env, addressUrl);
        console.log(string(abi.encodePacked(name, "_BLOCK=", (block.number).toString())));
    }

    function _create2(string memory name, string memory varName, bytes32 salt, bytes memory initCode) private returns (address addr) {
        bytes32 codeHash = keccak256(initCode);
        addr = vm.computeCreate2Address(salt, codeHash);
        if (addr.code.length > 0) {
            console.log(name, "already deployed");
        } else {
            assembly {
                addr := create2(0, add(initCode, 0x20), mload(initCode), salt)
                if iszero(addr) { revert(0, 0) }
            }
        }
        _printContract(varName, addr);
    }

    function _create3(string memory name, string memory varName, bytes32 salt, bytes memory initCode) private returns (address addr) {
        addr = CREATE3.predictDeterministicAddress(salt);
        if (addr.code.length > 0) {
            console.log(name, "already deployed");
        } else {
            addr = CREATE3.deployDeterministic(initCode, salt);
            _printContract(varName, addr);
        }
    }

    modifier broadcaster() {
        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }

    function _deploy(string memory name, string memory varName, bytes32 salt, bytes memory initCode) internal broadcaster returns (address addr) {
        return _create2(name, varName, salt, initCode);
    }

    function _envString(string memory name) internal view returns (string memory value) {
        value = vm.envString(name);
        console.log(string(abi.encodePacked(name, ": '", value, "'")));
    }

    function _envAddress(string memory name) internal view returns (address value) {
        value = vm.envAddress(name);
        console.log(string(abi.encodePacked(name, ": '", value.toHexString(), "'")));
    }

    function _envBytes32(string memory name) internal view returns (bytes32 value) {
        value = vm.envBytes32(name);
        console.log(string(abi.encodePacked(name, ": '", uint256(value).toHexString(), "'")));
    }

    function _envOr(string memory name, address defaultValue) internal view returns (address value) {
        value = vm.envOr(name, defaultValue);
        console.log(string(abi.encodePacked(name, ": '", value.toHexString(), "'")));
    }

    function _envUint(string memory name) internal view returns (uint256 value) {
        value = vm.envUint(name);
        console.log(string(abi.encodePacked(name, ": ", value.toString())));
    }
}
