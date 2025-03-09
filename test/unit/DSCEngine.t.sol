// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
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
    address public wbtcUsdPriceFeed;
    address public weth;
    address public wbtc;
    address public immutable USER = makeAddr("User");
    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    function setUp() external {
        deployer = new DeployDsc();
        (dsc, dsce, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }
    // Constructor Test

    function test_RevertIfInitialArrayLengthIsNotEqual() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(IDSCEngine.DSCEngine__NotMatchedLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function test_TokenAddressesAndPriceFeedAddressesMappingIsSetCorrectly() public {
        /**
         * tokenAddresses[0] = weth;
         *     tokenAddresses[1] = wbtc;
         *     priceFeedAddresses[0] = wethUsdPriceFeed;
         *     priceFeedAddresses[1] = wbtcUsdPriceFeed;
         *     这是不对的，因为tokenAddresses和priceFeedAddresses一开始被声明为空数组，当尝试通过索引直接访问并赋值（如tokenAddresses[0] = weth;）时，因为数组长度为0，所以任何索引访问都会越界
         */
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        DSCEngine _DSCEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        assertEq(weth, _DSCEngine.s_collateralTokens(0));
        assertEq(wbtc, _DSCEngine.s_collateralTokens(1));
        assertEq(wethUsdPriceFeed, _DSCEngine.getPriceFeedAddress(weth));
        assertEq(wbtcUsdPriceFeed, _DSCEngine.getPriceFeedAddress(wbtc));
    }

    //  Price Test

    function test_GetUsdValue() public {
        uint256 _ethAmount = 1 ether;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 _expectedUsd = 2_000e18;
        uint256 _usdValue = dsce.getUsdValue(weth, _ethAmount);
        assertEq(_expectedUsd, _usdValue);
    }

    function test_getTokenAmountFromUsd() public {
        uint256 _usdValue = 2000 ether;
        uint256 _expectedTokenAmountInEth = 1 ether;
        uint256 _tokenAmountFromUsd = dsce.getTokenAmountFromUsd(weth, _usdValue);
        assertEq(_expectedTokenAmountInEth, _tokenAmountFromUsd);
    }

    // Deposit Test

    function test_RevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(IDSCEngine.DSCEngine__InvalidAmount.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertIfCollateralIsNotAllowed() public {
        ERC20Mock _fakerToken = new ERC20Mock();
        vm.startPrank(USER);
        ERC20Mock(_fakerToken).mint(USER, AMOUNT_COLLATERAL);
        uint256 balanceAfterMint = _fakerToken.balanceOf(USER);
        console.log("User token balance after mint:", balanceAfterMint);
        ERC20Mock(_fakerToken).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(IDSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(_fakerToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startBroadcast(USER);
        // 在 setUp 中已经给 USER 铸造 weth 了,所以这里不需要再铸造
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopBroadcast();
        _;
    }

    function test_depositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(dsce));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_depositCollateralUpdatesState() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 _expectedDscMinted = 0;
        uint256 _expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL); // 计算存入 weth 的美元价值是否正确
        // uint256 _expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd); // 计算存入 weth数量是否正确
        assertEq(totalDscMinted, _expectedDscMinted);
        assertEq(collateralValueInUsd, _expectedCollateralValueInUsd);
        // assertEq(_expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    function test_multipleDepositsIncreaseTotalCollateral() public {
        // 第一次存款
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL * 2);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 firstDepositAmount = dsce.getUserDepositedAmount(USER, weth);
        // 第二次存款
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 totalDepositAmount = dsce.getUserDepositedAmount(USER, weth);
        vm.stopPrank();
        // 验证两次存款累加
        assertEq(totalDepositAmount, firstDepositAmount + AMOUNT_COLLATERAL);
        assertEq(totalDepositAmount, AMOUNT_COLLATERAL * 2);
    }
}
