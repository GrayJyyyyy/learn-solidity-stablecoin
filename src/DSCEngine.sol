// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IDSCEngine} from "./interface/IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is IDSCEngine, ReentrancyGuard {
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200%超额抵押
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%的激励
    DecentralizedStableCoin public immutable i_dsc;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_dscMinted;
    address[] public s_collateralTokens;

    modifier validAmount(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__InvalidAmount();
        }
        _;
    }

    modifier validAddress(address _address) {
        if (_address == address(0)) {
            revert DSCEngine__InvalidAddress();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__NotMatchedLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool _isSuccess = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!_isSuccess) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address _user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[_user];
        collateralValueInUsd = getAccountCollateralValue(_user);
    }
    /**
     * @notice 计算用户账户的健康因子
     * @param _user 用户地址
     * @dev 健康因子是衡量用户抵押品相对于借出稳定币的安全程度的指标
     * @dev 计算公式: (抵押品价值 * 清算阈值 / 清算精度) * PRECISION / 已铸造DSC数量
     * @dev 清算阈值设为50意味着只计入50%的抵押品价值，实际要求200%的超额抵押率
     * @dev 健康因子低于1时账户将面临清算风险
     * @dev 使用PRECISION(1e18)确保可以精确表示小于1的健康因子
     * @return healthFactor 用户的健康因子，以1e18为精度单位
     */

    function _getHealthFactor(address _user) private view returns (uint256 healthFactor) {
        // 获取用户已铸造的DSC数量和所有抵押品的美元价值
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(_user);

        // 简单的健康因子计算方式: healthFactor = collateralValueInUsd / totalDscMinted
        // 但这无法反映系统要求的超额抵押率和清算阈值

        // 根据清算阈值调整抵押品价值（仅计入50%）
        // 这创建了要求200%抵押率的系统 (100/50 = 2, 即200%)
        uint256 _collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // 计算最终健康因子，乘以PRECISION保留精度
        // 例如: 1000美元抵押，铸造400美元DSC
        // 调整后抵押品 = (1000 * 50) / 100 = 500
        // 健康因子 = 500 * 1e18 / 400 = 1.25 * 1e18
        healthFactor = (_collateralAdjustedForThreshold * PRECISION) / totalDscMinted;

        // 健康因子结果解释:
        // > 1 * 1e18: 账户状态健康
        // = 1 * 1e18: 账户处于临界点
        // < 1 * 1e18: 账户可能被清算
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 _healthFactor = _getHealthFactor(user);
        if (_healthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorTooLow(_healthFactor);
        }
    }

    // 与外部合约交互，需要防止重入攻击
    // 遵循 CEI原则：检查-影响-互动
    // 1.检查 装饰器提前检查参数
    // 2.影响 执行函数逻辑,修改状态
    // 3.互动 与外部合约交互
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        override
        // Check
        nonReentrant
        validAmount(_amountCollateral)
        validAddress(_tokenCollateralAddress)
        isAllowedToken(_tokenCollateralAddress)
    {
        // Effect
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        // Interaction
        bool _success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!_success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function mintDsc(uint256 _amountDesToMint) public validAmount(_amountDesToMint) nonReentrant {
        s_dscMinted[msg.sender] += _amountDesToMint;
        // 保证200%超额抵押率
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDesToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function getAccountCollateralValue(address _user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address _token = s_collateralTokens[i];
            uint256 _amount = s_collateralDeposited[_user][_token];
            totalCollateralValueInUsd += getUsdValue(_token, _amount);
        }
    }

    function getUsdValue(address _token, uint256 _amount) public view returns (uint256 usdValue) {
        AggregatorV3Interface _priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        /**
         * 小数位数是8 如果1ETH=$1000,这个函数会返回1000*1e8，可以从下面文档得知：
         * https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1&search=eth+%2F+usd
         */
        (, int256 _price,,,) = _priceFeed.latestRoundData();
        /**
         * 使用ADDITIONAL_FEED_PRECISION以及PRECISION的原因
         * 标准化精度：
         *
         * 确保所有金融计算都统一使用18位小数精度（1e18），这是以太坊生态系统中的常见标准
         * 使得合约内部和与外部系统交互时的数值表示保持一致
         *
         *
         * 防止溢出：
         *
         * 通过适当安排乘法和除法的顺序，避免中间计算结果超出uint256的范围
         * 特别是在处理大量代币或高价值资产时，不正确的计算顺序可能导致溢出
         *
         *
         * 避免精度损失：
         *
         * Solidity中的整数除法会舍弃小数部分
         * 先进行乘法再除以精度因子，可以最大限度地保留计算精度
         */
        usdValue = (uint256(_price) * ADDITIONAL_FEED_PRECISION * _amount) / PRECISION;
    }

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        validAmount(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _burnDsc(uint256 amountToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountToBurn;
        bool _isSuccess = i_dsc.transferFrom(
            dscFrom,
            address(this), // this 总是指向当前合约实例,在这里就是 DSCEngine
            amountToBurn
        );
        if (!_isSuccess) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountToBurn);
    }
    /**
     * 在 burnDsc 函数中不需要检查健康因子的原因：
     * 健康因子是衡量风险的指标：健康因子是用来确保用户有足够的抵押品来支持他们铸造的 DSC 代币。健康因子的计算公式是：(抵押品价值 * 清算阈值 / 清算精度) * PRECISION / 已铸造DSC数量。
     * 销毁操作永远不会使健康因子恶化：当用户销毁 DSC 代币时，他们实际上是在减少自己的债务（s_dscMinted[msg.sender]），这只会改善（提高）他们的健康因子，而不会恶化它。
     * 数学上的解释：
     * 健康因子 = (抵押品价值 * 清算阈值 / 清算精度) * PRECISION / 已铸造DSC数量
     * 当 DSC 数量（分母）减少时，健康因子（结果）会增加
     * 因此，销毁 DSC 永远不会导致健康因子下降到危险水平
     * 检查的必要性：
     * 铸造 DSC 时需要检查健康因子，因为增加债务会降低健康因子
     * 赎回抵押品时需要检查健康因子，因为减少抵押品会降低健康因子
     * 销毁 DSC 时不需要检查健康因子，因为减少债务只会提高健康因子
     */

    function burnDsc(uint256 amountToBurn) public validAmount(amountToBurn) {
        _burnDsc(amountToBurn, msg.sender, msg.sender);
    }

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBurn)
        external
    {
        burnDsc(amountToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function getTokenAmountFromUsd(address tokenCollateralAddress, uint256 usdAmountInWei)
        public
        returns (uint256 usdValue)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        usdValue = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        public
        validAmount(debtToCover)
        validAddress(tokenCollateralAddress)
        validAddress(user)
        nonReentrant
    {
        uint256 _startingUserHealthFactor = _getHealthFactor(user);
        if (_startingUserHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOk();
        }
        uint256 _tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        uint256 _bonusCollateral = (_tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 _totalCollateralToRedeem = _bonusCollateral + _tokenAmountFromDebtCovered;
        _redeemCollateral(user, msg.sender, tokenCollateralAddress, _totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 _endingUserHealthFactor = _getHealthFactor(user);
        if (_endingUserHealthFactor <= _startingUserHealthFactor) {
            revert DSCEngine__HealthFactorIsNotImproved();
        }
        _revertIfHealthFactorIsBroken(user);
    }
}
