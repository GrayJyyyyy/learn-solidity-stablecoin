// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDSCEngine} from "./interface/IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import {HelperConfig} from "../../script/HelperConfig.s.sol";

abstract contract DSCEngine is IDSCEngine, ReentrancyGuard {
    // HelperConfig public helperConfig;

    DecentralizedStableCoin public immutable i_dsc;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    modifier validAmount(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine_InvalidAmount();
        }
        _;
    }

    modifier validAddress(address _address) {
        if (_address == address(0)) {
            revert DSCEngine_InvalidAddress();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine_NotAllowedToken();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_NotMatchedLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    // 与外部合约交互，需要防止重入攻击
    // 遵循 CEI原则：检查-影响-互动
    // 1.检查 装饰器提前检查参数
    // 2.影响 执行函数逻辑,修改状态
    // 3.互动 与外部合约交互
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        external
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
            revert DSCEngine_TransferFailed();
        }
    }
}
