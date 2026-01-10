// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/Factory.sol"; 
import "../contracts/test/ERC20Mock.sol"; 

contract FactoryTest is Test {
    Pool pool;
    ERC20Mock token0;
    ERC20Mock token1;

    address user = address(0xBEEF);

    function setUp() public {
        token0 = new ERC20Mock("Token 0", "TK0", address(this), 1000 ether);
        token1 = new ERC20Mock("Token 1", "TK1", address(this), 1000 ether);
        
        // Деплоим пул напрямую для теста
        pool = new Pool(address(token0), address(token1));
    }

    function test_InitialBalancesAreZero() public view {
        assertEq(token0.balanceOf(address(pool)), 0);
        assertEq(token1.balanceOf(address(pool)), 0);
    }

    function test_TransferToPool() public {
        // Даем нашему виртуальному пользователю токены
        // vm.deal работает для ETH, а для токенов мы просто переведем их от себя
        token0.transfer(user, 100 ether);
        
        // Теперь мы хотим проверить, что USER может отправить токены в пул
        // Включаем "режим пользователя"
        vm.prank(user); 
        token0.transfer(address(pool), 50 ether);

        assertEq(token0.balanceOf(address(pool)), 50 ether);
        assertEq(token0.balanceOf(user), 50 ether);
    }

    function testFuzz_TransferToPool(uint256 amount) public {
        // 1. Ограничиваем сумму, чтобы она не была больше, чем мы дали пользователю
        // И чтобы она не была нулевой 
        vm.assume(amount > 0 && amount <= 1000 ether);

        // 2. Даем пользователю токены
        token0.transfer(user, amount);
        
        // 3. Пользователь переводит в пул
        vm.prank(user); 
        token0.transfer(address(pool), amount);

        // 4. Проверяем баланс пула
        assertEq(token0.balanceOf(address(pool)), amount);
}

   
}