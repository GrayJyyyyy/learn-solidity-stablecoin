// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {IDSCEngine} from "../../src/interface/IDSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mock/MockFailedTransferFrom.sol";
import {MockFailedMintDSC} from "../mock/MockFailedMintDSC.sol";

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
    address public immutable LIQUIDATOR = makeAddr("Liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200%超额抵押
    uint256 private constant LIQUIDATION_PRECISION = 100;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    );

    function setUp() external {
        deployer = new DeployDsc();
        (dsc, dsce, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, 10 * STARTING_ERC20_BALANCE);
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

    // modifier
    modifier depositCollateral() {
        vm.startBroadcast(USER);
        /**
         * 正常操作流程：
         *  首先要确保用户有资金，在这里是 weth，所以要先 mint，这一步在 setUp 里已经做了所以这里不需要再 mint
         *  然后就是调用approve授权 dsce 合约操作用户的代币
         */
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopBroadcast();
        _;
    }

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        // 计算可以安全铸造的 DSC 数量
        // 假设我们想保持健康因子在安全水平，这里使用 AMOUNT_COLLATERAL价值的四分之一 500DSC
        uint256 collateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        // 铸造抵押品价值的 1/4 (为保持安全性)
        // 健康因子 = (2000 * 50/100) * 1e18 / 500 = 1000 * 1e18 / 500 = 2e18 = 2.0
        uint256 dscToMint = collateralValueInUsd / 4;
        dsce.mintDsc(dscToMint);
        vm.stopPrank();
        _;
    }
    //  Price Test

    function test_GetAccountCollateralValue() public depositCollateral {
        uint256 _totalCollateralValueInUsd = dsce.getAccountCollateralValue(USER);
        uint256 _calculatedUsdValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(_totalCollateralValueInUsd, _calculatedUsdValue);
    }

    function test_GetUsdValue() public {
        uint256 _ethAmount = 1 ether;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 _expectedUsd = 2_000e18;
        uint256 _usdValue = dsce.getUsdValue(weth, _ethAmount);
        assertEq(_expectedUsd, _usdValue);
    }

    function test_GetTokenAmountFromUsd() public {
        uint256 _usdValue = 2000 ether;
        uint256 _expectedTokenAmountInEth = 1 ether;
        uint256 _tokenAmountFromUsd = dsce.getTokenAmountFromUsd(weth, _usdValue);
        assertEq(_expectedTokenAmountInEth, _tokenAmountFromUsd);
    }

    // Deposit Test

    function test_RevertIfMintIsFailed() public {
        tokenAddresses = [weth];
        priceFeedAddresses = [wethUsdPriceFeed];
        MockFailedMintDSC _dsc = new MockFailedMintDSC();
        DSCEngine _mockDSCEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(_dsc));
        _dsc.transferOwnership(address(_mockDSCEngine));
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(_mockDSCEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(IDSCEngine.DSCEngine__MintFailed.selector);
        _mockDSCEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

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

    function test_RevertIfAmountInvalid() public {
        vm.startPrank(USER);
        uint256 _amountCollateral = 0;
        vm.expectRevert(IDSCEngine.DSCEngine__InvalidAmount.selector);
        dsce.depositCollateral(weth, _amountCollateral);
        vm.stopPrank();
    }

    function test_DepositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(dsce));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_DepositCollateralUpdatesState() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 _expectedDscMinted = 0;
        uint256 _expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL); // 计算存入 weth 的美元价值是否正确
        // uint256 _expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd); // 计算存入 weth数量是否正确
        assertEq(totalDscMinted, _expectedDscMinted);
        assertEq(collateralValueInUsd, _expectedCollateralValueInUsd);
        // assertEq(_expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    function test_MultipleDepositsIncreaseTotalCollateral() public {
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

    function test_RevertIfTransferFromIsFailed() public {
        MockFailedTransferFrom _tokenForCollateral = new MockFailedTransferFrom();
        tokenAddresses = [address(_tokenForCollateral)];
        priceFeedAddresses = [wethUsdPriceFeed];
        // 使用dsc作为稳定币
        DSCEngine _mockDSCEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        // 为用户铸造代币
        _tokenForCollateral.mint(USER, STARTING_ERC20_BALANCE);
        // 切换到USER身份执行测试
        vm.startPrank(USER);
        _tokenForCollateral.approve(address(_mockDSCEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(IDSCEngine.DSCEngine__TransferFailed.selector);
        _mockDSCEngine.depositCollateral(address(_tokenForCollateral), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // Mint test
    function test_RevertIfHealthFactorIsBrokenWhenMint() public depositCollateral {
        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 _maxDscToMint = collateralValueInUsd * 50 / 100;
        uint256 _exceedingAmount = _maxDscToMint + 1 ether;
        vm.startPrank(USER);
        vm.expectPartialRevert(IDSCEngine.DSCEngine__HealthFactorTooLow.selector);
        dsce.mintDsc(_exceedingAmount);
        vm.stopPrank();
    }

    // Redeem test
    function test_RevertIfRedeemAmountIsZero() public depositCollateral {
        uint256 _invalidAmount = 0;
        vm.startPrank(USER);
        vm.expectRevert(IDSCEngine.DSCEngine__InvalidAmount.selector);
        dsce.redeemCollateral(weth, _invalidAmount);
    }

    function test_RedeemCollateralUpdatesState() public depositCollateralAndMintDsc {
        // 价值相当于 20 美元的抵押物
        uint256 _amountToRedeem = dsce.getTokenAmountFromUsd(weth, 20 ether);
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, _amountToRedeem);
        uint256 _collateralDeposited = AMOUNT_COLLATERAL - _amountToRedeem;
        assertEq(_collateralDeposited, dsce.getUserDepositedAmount(USER, weth));
    }

    function test_RedeemCollateralEmitEvents() public depositCollateralAndMintDsc {
        uint256 _amountToRedeem = dsce.getTokenAmountFromUsd(weth, 20 ether);
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, weth, _amountToRedeem);
        dsce.redeemCollateral(weth, _amountToRedeem);
    }
}
