// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Pool is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public token0;
    address public token1;
    uint112 private reserve0; 
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    uint256 constant FEE_NUM = 3; 
    uint256 constant FEE_DEN = 1000;
    uint256 constant MINIMUM_LIQUIDITY = 1000;
    address constant BURN_ADDR = 0x000000000000000000000000000000000000dEaD;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    address public factory;

    constructor(address _token0, address _token1)
    ERC20("Uniswap V2", "UNI-V2")
    {
    require(_token0 != _token1, "IDENTICAL_ADDRESSES");
    require(_token0 != address(0) && _token1 != address(0), "ZERO_ADDRESS");

    token0 = _token0;
    token1 = _token1;
    factory = msg.sender;
    }   
    

    function sqrt(uint256 y) internal pure returns (uint256 z) {
     if (y > 3) {
        z = y;
        uint x = y / 2 + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
     } else if (y != 0) {
        z = 1;
     }
     return z;
    }

    function getReserves() public view returns (uint112, uint112, uint32){
         return (reserve0, reserve1, blockTimestampLast);
    }

     function _update(uint256 balance0, uint256 balance1) internal{
        require(balance0 <= type(uint112).max, "overflow in _update");
        require(balance1 <= type(uint112).max, "overflow in _update");
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }

    function mint(address to) external returns (uint256 liquidity) {

       // получаем новые балансы в реальном времени
      uint256 balance0 = IERC20(token0).balanceOf(address(this));
      uint256 balance1 = IERC20(token1).balanceOf(address(this));

      require(balance0 >= reserve0 && balance1 >= reserve1, "INSUFFICIENT_BALANCE");

     // вычитываем разницу, сколько мы реально внесли: новый баланс - старый баланс = то что мы внесли
      uint256 amount0 = balance0 - reserve0;
      uint256 amount1 = balance1 - reserve1;

     // общая эмиссия всех LP токенов
      uint256 _totalSupply = totalSupply();
      require(amount0 > 0 && amount1 > 0, "INSUFFICIENT_INPUT");

     if(_totalSupply == 0){
      liquidity = sqrt(amount0 * amount1);
       require(liquidity > MINIMUM_LIQUIDITY, "MINIMUM_LIQUIDITY");
     // Первые 1000 LP сжигать (как в Uniswap)
        _mint(BURN_ADDR, MINIMUM_LIQUIDITY); 
        liquidity -= MINIMUM_LIQUIDITY;
     }else{
        uint256 liquidity0 = amount0 * _totalSupply / reserve0;
        uint256 liquidity1 = amount1 * _totalSupply / reserve1;
        liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
     }

       require(liquidity > 0, "Insufficient liquidity minted");

        _mint(to, liquidity);
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);

        return liquidity;
    }
    
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = balanceOf(address(this));
        require(liquidity > 0, "NO_LIQUIDITY");
        uint256 _totalSupply = totalSupply();

        amount0 = liquidity * reserve0 / _totalSupply;
        amount1 = liquidity * reserve1 / _totalSupply;
        _burn(address(this), liquidity);


        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1);
        emit Burn(msg.sender, amount0, amount1, to);
        return (amount0, amount1);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant {
        uint256 balance0;
        uint256 balance1;
        uint256 amount0In;
        uint256 amount1In;
        uint256 _reserve0 = reserve0;
        uint256 _reserve1 = reserve1;
        require(amount0Out > 0 || amount1Out > 0, "Uncorrect swap balance");
        require(amount0Out < _reserve0, "reserve must be bigger than amount out");
        require(amount1Out < _reserve1, "reserve must be bigger than amount out");
        require(to != address(0) && to != address(this), "incorrect address");
        require(to != token0 && to != token1, "to can't be token0 or token1 in swap");
       if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
       if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

        // read new balances
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));


        // calculate the input amounts
        amount0In = balance0 > (_reserve0 - amount0Out) ? balance0 - (_reserve0 - amount0Out) : 0;
        amount1In = balance1 > (_reserve1 - amount1Out) ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount1In > 0 || amount0In > 0, "user must pay at least something");

        // math x * y = k
        uint256 balance0Adjusted = balance0 * FEE_DEN - amount0In * FEE_NUM;
        uint256 balance1Adjusted = balance1 * FEE_DEN - amount1In * FEE_NUM;
        require(balance0Adjusted * balance1Adjusted >= _reserve0 * _reserve1 * FEE_DEN * FEE_DEN, "K");

        _update(balance0, balance1);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);

    }
}