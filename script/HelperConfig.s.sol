// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/local/src/data-feeds/MockV3Aggregator.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_ANSWER_FOR_ETH = 2000 * 1e8;
    int256 public constant INITIAL_ANSWER_FOR_BTC = 50000 * 1e8;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory config) {
        config = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc: 0x16EFdA168bDe70E05CA6D349A690749d622F95e0,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory config) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER_FOR_ETH);
        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER_FOR_BTC);
        vm.stopBroadcast();
        config = NetworkConfig({
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc),
            // deployerKey: vm.envUint("PRIVATE_KEY")
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
