// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Test.sol";
import { IERC20, TestContext } from "test/common/TestContext.sol";

interface IERC20Mint is IERC20 {
    function mint(address account, uint256 value) external returns (bool);
}

contract TestContextSepolia is TestContext {
    mapping(string => address) public tokenOwners;

    constructor(Vm vm_) TestContext(vm_) {
        vm.createSelectFork("sepolia");
        contracts["USDC"] = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
        tokenOwners["USDC"] = 0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D;
        contracts["WBTC"] = 0xAe7C08f2FC56719b8F403C29F02E99CF809F8e34;
        tokenOwners["WBTC"] = 0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D;
    }

    function mint(string memory tokenName, string memory walletName, uint256 amount) public override returns (address wallet) {
        wallet = createWallet(walletName);
        IERC20Mint token = IERC20Mint(address(createERC20Token(tokenName)));
        vm.prank(tokenOwners[walletName]);
        token.mint(wallet, amount);
        return wallet;
    }

    // function createRoycoWrappedVaultFactory() public virtual returns (TestContext.RoycoContracts memory royco) {
    //     royco.pointsFactory = PointsFactory(0x91CB34602661aBABb7D120574830371D3243113b);
    //     royco.weirollWallet = WeirollWallet(payable(0x873F4d2484f73Fa48f48007Db212Bf92e5F39659));
    //     royco.vaultOrderbook = VaultOrderbook(0x09ccdBBb97Fc0c5160CEbcCdcCAc13eE1C88Fbcb);
    //     royco.erc4626iFactory = ERC4626iFactory(0xa0b12Cc86D5c89478B85A1968c4551Ba23FFE5AA);
    //     royco.recipeOrderbook = RecipeOrderbook(0xd53A273656C40ea03B865babE10B6F51a863946f);
    // }
}
