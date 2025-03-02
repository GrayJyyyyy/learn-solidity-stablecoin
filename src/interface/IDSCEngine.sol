// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * 用户的抵押品总价值应当始终大于等于其所持DSC的价值
 */
interface IDSCEngine {
    error DSCEngine__InvalidAmount();
    error DSCEngine__InvalidAddress();
    error DSCEngine__NotMatchedLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorTooLow(uint256 _healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsOk();
    error DSCEngine__HealthFactorIsNotImproved();

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    );
    // 组合函数:抵押并铸造DSC
    /**
     * @param tokenCollateralAddress 抵押品地址
     * @param amountCollateral 抵押品数量
     */

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external;
    // 组合函数:返还DSC取回抵押品
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBurn)
        external;

    // 抵押函数
    /**
     * @param tokenCollateralAddress 抵押品地址
     * @param amountCollateral 抵押品数量
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;
    // 铸造函数 因为抵押物的总价值必须大于等于 DSC 的价值，所以每次铸造前都需要先判断用户抵押物是否足够。因此需要一个变量记录每个用户当前已铸造的DSC数量
    function mintDsc(uint256 amountDscToMint) external;
    // 赎回抵押物函数
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;
    // 销毁DSC
    function burnDsc(uint256 amountToBurn) external;
    // 清算
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover) external;
}
