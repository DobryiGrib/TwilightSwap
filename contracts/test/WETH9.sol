// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WETH9 is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    // Функция для создания WETH из присланного ETH
    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    // Функция для вывода ETH
    function withdraw(uint256 amount) public {
        require(balanceOf(msg.sender) >= amount, "Insufficient WETH balance");
        _burn(msg.sender, amount);
        payable(msg.sender).call{value: amount}("");
    }

    // Позволяет просто отправлять ETH на контракт для получения WETH
    receive() external payable {
        deposit();
    }
}