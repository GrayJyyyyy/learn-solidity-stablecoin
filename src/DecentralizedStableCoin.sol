// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error DecentralizedStableCoin_InvalidAmount();
error DecentralizedStableCoin_InsufficientBalance();
error DecentralizedStableCoin_InvalidAddress();

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 _currentBalance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin_InvalidAmount();
        }
        if (_currentBalance < _amount) {
            revert DecentralizedStableCoin_InsufficientBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin_InvalidAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin_InvalidAmount();
        }
        _mint(_to, _amount);
        return true;
    }
}
