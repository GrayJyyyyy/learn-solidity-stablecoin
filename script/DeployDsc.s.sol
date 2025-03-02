// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDsc is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin dsc, DSCEngine engine, HelperConfig config) {
        config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.startBroadcast(deployerKey); // 只有实际需要部署上链的合约才需要包裹在startBroadcast和stopBroadcast之间
        DecentralizedStableCoin _dsc = new DecentralizedStableCoin();
        DSCEngine _engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(_dsc));
        _dsc.transferOwnership(address(_engine)); // _dsc一开始的所有者是deployer，现在转给engine
        vm.stopBroadcast();
        dsc = _dsc;
        engine = _engine;
    }
}
