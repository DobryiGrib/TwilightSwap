// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/Router.sol";
import "../contracts/Factory.sol";
import "../contracts/test/ERC20Mock.sol";
import "../contracts/test/WETH9.sol"; 
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RouterTest is Test {
    Router router;
    Factory factory;
    WETH9 weth;
    ERC20Mock token;
    
    address user = address(0x1);

    function setUp() public {
        // 1. Сначала деплоим зависимости
        weth = new WETH9();
        factory = new Factory(); // Владельцем станет этот контракт теста
        
        // 2. Деплоим сам Роутер
        router = new Router(address(factory), address(weth));
        
        // 3. Создаем тестовый токен и даем его пользователю
        token = new ERC20Mock("Test Token", "TT", address(this), 1000 ether);
        token.transfer(user, 100 ether);

        // 4. Даем пользователю немного реального ETH для ликвидности
        vm.deal(user, 10 ether); // Чит-код vm.deal начисляет нативный ETH
    }

    //test for add liquidity
    function test_AddLiquidity() public {
        uint256 tokenAmount = 10 ether;
        uint256 ethAmount = 1 ether;

        vm.startPrank(user); // Начинаем серию действий от лица пользователя

        // 1. Разрешаем Роутеру тратить наши токены
        token.approve(address(router), tokenAmount);

        // 2. Добавляем ликвидность
        router.addLiquidityETH{value: ethAmount}(
            address(token),
            tokenAmount,
            0, // min token (для теста ставим 0)
            0, // min eth (для теста ставим 0)
            user,
            block.timestamp + 15 // дедлайн
        );

        vm.stopPrank();

        // 3. ПРОВЕРКИ (Assertions)
        address pairAddress = factory.getPair(address(token), address(weth));
        
        // Проверяем, что в пуле теперь лежат наши токены
        assertEq(token.balanceOf(pairAddress), tokenAmount);
        // Проверяем, что в пуле теперь лежит наш WETH
        assertEq(weth.balanceOf(pairAddress), ethAmount);

        uint256 lpbalance = IERC20(pairAddress).balanceOf(user);
        assertGt(lpbalance, 0 ether);
    }

    //test for swap exact ETH fot tokens
    function test_SwapETHForTokens() public {
        // 1. Сначала добавляем ликвидность (копируем логику выше)
        uint256 liquidityToken = 100 ether;
        uint256 liquidityETH = 1 ether;
        
        token.approve(address(router), liquidityToken);
        router.addLiquidityETH{value: liquidityETH}(
            address(token), liquidityToken, 0, 0, address(this), block.timestamp
        );

        // 2. Подготовка к обмену
        uint256 swapAmountIn = 0.1 ether; // Сколько ETH отдаем
        address[] memory path = new address[](2);
        path[0] = address(weth); // Из WETH
        path[1] = address(token); // В наш токен

        // Запоминаем баланс ДО
        uint256 balanceBefore = token.balanceOf(user);

        // 3. Делаем обмен от лица пользователя
        vm.prank(user);
        router.swapExactETHForTokens{value: swapAmountIn}(
            0, // min amount out (для теста 0)
            path,
            user,
            block.timestamp + 15
        );

        // 4. ПРОВЕРКА
        uint256 balanceAfter = token.balanceOf(user);
        assertGt(balanceAfter, balanceBefore); // Токенов должно стать больше
    }

    //test for removeLiquidity
    function test_RemoveLiquidityETH() public {
          // 1. Сначала добавляем ликвидность 
        uint256 liquidityToken = 100 ether;
        uint256 liquidityETH = 1 ether;
        
        vm.startPrank(user);
        token.approve(address(router), liquidityToken);
        router.addLiquidityETH{value: liquidityETH}(
            address(token), liquidityToken, 0, 0, user, block.timestamp
        );

        uint256 balanceTokenBefore = token.balanceOf(user);
        uint256 balanceETHBefore = weth.balanceOf(user);
        address pairAddress = factory.getPair(address(token), address(weth));
        uint256 lpbalance = IERC20(pairAddress).balanceOf(user);

        
        IERC20(pairAddress).approve(address(router), lpbalance);
        router.removeLiquidityETH(address(token), lpbalance, 0, 0, user, block.timestamp + 15);

        vm.stopPrank();
        assertEq(IERC20(pairAddress).balanceOf(user), 0);
        assertGt(address(user).balance, balanceETHBefore);
        assertGt(token.balanceOf(user), balanceTokenBefore);

    }

    // test revert for slippage
    function test_RevertSlipageSwapETHForTokens() public {
        // 1. Сначала добавляем ликвидность 
        uint256 liquidityToken = 100 ether;
        uint256 liquidityETH = 1 ether;
        
        vm.startPrank(user);
        token.approve(address(router), liquidityToken);
        router.addLiquidityETH{value: liquidityETH}(
            address(token), liquidityToken, 0, 0, user, block.timestamp
        );
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        vm.expectRevert("INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactETHForTokens{value: 0.1 ether}(9.5 ether, path, user, block.timestamp + 15);
        vm.stopPrank();
      
    }

    // test for check comission 0.3%
    function test_CheckCommisionForSwap() public{
         // 1. Сначала добавляем ликвидность 
        uint256 liquidityToken = 100 ether;
        uint256 liquidityETH = 1 ether;
        
        vm.startPrank(user);
        token.approve(address(router), liquidityToken);
        router.addLiquidityETH{value: liquidityETH}(
            address(token), liquidityToken, 0, 0, user, block.timestamp
        );
        address pairAddress = factory.getPair(address(token), address(weth));
        uint256 balancePoolBefore = IERC20(token).balanceOf(pairAddress) * IERC20(weth).balanceOf(pairAddress);
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);
        router.swapExactETHForTokens{value: 0.01 ether}(0, path, user, block.timestamp + 15);
        uint256 balancePoolAfter = IERC20(token).balanceOf(pairAddress) * IERC20(weth).balanceOf(pairAddress);
        assertGt(balancePoolAfter, balancePoolBefore);
        vm.stopPrank();
    }

    // test fuzzing
    function testFuzz_SwapAmount(uint256 amount) public {

        // Это единственный чит-код, который мы оставим для логики
        amount = bound(amount, 1, 10 ether); 

        // 2. Добавляем ликвидность (база)
        uint256 initialLiquidity = 100 ether;
        token.approve(address(router), initialLiquidity);
        router.addLiquidityETH{value: 10 ether}(
            address(token), initialLiquidity, 0, 0, address(this), block.timestamp
        );

        // 3. Пытаемся сделать обмен на СЛУЧАЙНУЮ сумму amount
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        // Даем юзеру ETH для обмена 
        vm.deal(user, amount);

        vm.prank(user);
        // Если твоя математика обмена x*y=k верна, это должно работать для любого amount
        router.swapExactETHForTokens{value: amount}(
            0, 
            path,
            user,
            block.timestamp
        );

        // 4. Проверка
        assertGt(token.balanceOf(user), 0, "User should receive tokens");
    }



}