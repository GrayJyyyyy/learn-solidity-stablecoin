// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
/**
 * 用户的抵押品总价值应当始终大于等于其所持DSC的价值
 */

interface IDSCEngine {
    error DSCEngine_InvalidAmount();
    error DSCEngine_InvalidAddress();
    error DSCEngine_NotMatchedLength();
    error DSCEngine_NotAllowedToken();
    error DSCEngine_TransferFailed();

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    // 组合函数:抵押并铸造DSC
    /**
     * @param tokenCollateralAddress 抵押品地址
     * @param amountCollateral 抵押品数量
     */

    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral) external;
    // 组合函数:返还DSC取回抵押品
    function redeemCollateralForDsc() external;

    // 抵押函数
    /**
     * @param tokenCollateralAddress 抵押品地址
     * @param amountCollateral 抵押品数量
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;
    // 铸造函数
    function mintDsc() external;
    // 赎回抵押物函数
    function redeemCollateral() external;
    // 销毁DSC
    function burnDsc() external;
    // 清算
    function liquidate() external;
    // 获取健康因子
    function getHealthFactor() external view returns (uint256);
}
