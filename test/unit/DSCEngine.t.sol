// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {IDSCEngine} from "../../src/interface/IDSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DECEngine is Test {
    DeployDsc public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;
    HelperConfig public helperConfig;
    address public wethUsdPriceFeed;
    address public weth;
    address public immutable USER = makeAddr("User");
    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployDsc();
        (dsc, dsce, helperConfig) = deployer.run();
        (wethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //  Price Test
    function test_GetUsdValue() public {
        uint256 ethAmount = 1 ether;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 2_000e18;
        uint256 usdValue = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, usdValue);
    }
    // Deposit Test

    function test_RevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(IDSCEngine.DSCEngine__InvalidAmount.selector);
        dsce.depositCollateral(weth, 0);
    }
}
