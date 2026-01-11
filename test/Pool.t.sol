pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/Pool.sol";
import "../contracts/Factory.sol";
import "../contracts/test/ERC20Mock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract PoolTest is Test{
    using SafeERC20 for IERC20;

    Pool pool;
    Factory factory;
    ERC20Mock token0;
    ERC20Mock token1;
    address user = address(0x1234);

      function setUp() public {
     
        factory = new Factory();
        
        token0 = new ERC20Mock("Test Token", "TT", address(this), 2000 ether);
        token1 = new ERC20Mock("Test Token", "TT", address(this), 2000 ether);
        token0.transfer(user, 1000 ether);
        token1.transfer(user, 1000 ether);
        pool = new Pool(address(token0), address(token1));

        // Даем пользователю немного реального ETH для ликвидности
        vm.deal(user, 10 ether); // Чит-код vm.deal начисляет нативный ETH
    }

  function test_InitialMint() public {
        token0.transfer(address(pool), 100 ether);
        token1.transfer(address(pool), 100 ether);
        
        pool.mint(address(this));

        // Корень из (100e18 * 100e18) = 100e18
        uint256 expected = 100 ether - 1000; 
        assertEq(pool.balanceOf(address(this)), expected);
        
        (uint112 res0, uint112 res1, ) = pool.getReserves();
        assertEq(res0, 100 ether);
        assertEq(res1, 100 ether);
    }

    function test_SwapTokens() public {
        // Ликвидность 100/100
        token0.transfer(address(pool), 100 ether);
        token1.transfer(address(pool), 100 ether);
        pool.mint(address(this));

        uint256 balanceBefore1 = token1.balanceOf(address(this));
        
        // Отправляем 10 токенов 0, хотим получить 5 токенов 1
        token0.transfer(address(pool), 10 ether);
        pool.swap(0, 5 ether, address(this)); 

        assertEq(token1.balanceOf(address(this)), balanceBefore1 + 5 ether);
    }

    function test_Burn() public{
        IERC20(token0).safeTransfer(address(pool), 100 ether);
        IERC20(token1).safeTransfer(address(pool), 100 ether);
        pool.mint(address(this));
        uint256 balanceBefore0 = IERC20(token0).balanceOf(address(this));
        uint256 balanceBefore1 = IERC20(token1).balanceOf(address(this));
        uint256 lpbalance = IERC20(pool).balanceOf(address(this));
        IERC20(pool).safeTransfer(address(pool), lpbalance);
        pool.burn(address(this));
        assertEq(IERC20(pool).balanceOf(address(this)), 0 ether);
        assertGt(IERC20(token0).balanceOf(address(this)), balanceBefore0 + 99.8 ether);
        assertGt(IERC20(token1).balanceOf(address(this)), balanceBefore1 + 99.8 ether);

    }
}
