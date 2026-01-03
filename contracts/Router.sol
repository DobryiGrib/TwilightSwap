// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
    function createPair(address tokenA, address tokenB) external returns (address);
}

interface IPool {
    function getReserves() external view returns (uint112, uint112, uint32);
    function mint(address to) external returns (uint256);
    function burn(address to) external returns (uint256, uint256); 
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external; 
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}

contract Router {
    using SafeERC20 for IERC20;

    IFactory public factory;
    address public immutable WETH;

    constructor(address _factory, address _WETH) {
        factory = IFactory(_factory);
        WETH = _WETH;
    }

    // Принимаем ETH только от контракта WETH
    receive() external payable {
        assert(msg.sender == WETH); 
    }

    // helper: sorts tokens so token0 < token1
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
    }

    // helper: given amountA and reserves, quote how much B is needed to keep price
    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256) {
        require(amountA > 0, "INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        return (amountA * reserveB) / reserveA;
    }

    function _calculateLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        // 1. Ищем или создаем пару через фабрику
        address pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = factory.createPair(tokenA, tokenB);
        }

        // 2. Достаем резервы
        (uint112 reserve0, uint112 reserve1, ) = IPool(pair).getReserves();
        (address token0, ) = _sortTokens(tokenA, tokenB);
        
        // присваиваем токены A&B по порядку
        (uint256 reserveA, uint256 reserveB) = tokenA == token0 
            ? (uint256(reserve0), uint256(reserve1)) 
            : (uint256(reserve1), uint256(reserve0));

        // первое условие, если пары нет то ты устанавливаешь цену, какую пропорцию внес такая и цена
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // если пара уже есть, заставляем соблюдать пропорцию чтобы цена не улетела
            uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
            // если нужное количество токена B хватает то забираем все желаемые токены A и нужную пропорцию токена B
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // если нужного количества токена B не хватает, берем все токены B и вычисляем сколько токенов A нужно для пропорции
                uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _swap(uint256[] memory amounts, address[] calldata path, address _to) internal {
      for (uint256 i; i < path.length - 1; i++) {
        // 1. Берем текущий токен и тот, на который меняем
        (address input, address output) = (path[i], path[i + 1]);

        // 2. Сортируем их, чтобы понять, какой из них в пуле идет первым (token0)
        (address token0, ) = _sortTokens(input, output);
        
        // 3. Сколько токенов мы должны вытащить из этого пула?
        // Это берется из заранее рассчитанного массива amounts
        uint256 amountOut = amounts[i + 1];
        
        // 4. Пул Uniswap V2 имеет два выхода: amount0Out и amount1Out.
        // Нам нужно понять, в какую "трубу" направить выход.
        // Решаем, в какую "дырку" пула (amount0 или amount1) выталкивать токены
        (uint256 amount0Out, uint256 amount1Out) = input == token0 
            ? (uint256(0), amountOut) 
            : (amountOut, uint256(0));

            // Находим текущую пару
        address pair = factory.getPair(input, output);
        // ПРОВЕРКА: Если пары нет, незачем идти дальше
        require(pair != address(0), "DEX: PAIR_DOES_NOT_EXIST");
            
        // Если это не последний обмен в цепочке, отправляем токены в следующий пул
        // Если это финал — отправляем сразу пользователю (_to).
        address recipient;
        if (i < path.length - 2) {
            recipient = factory.getPair(output, path[i + 2]);
            require(recipient != address(0), "DEX: NEXT_PAIR_DOES_NOT_EXIST");
        } else {
            recipient = _to;
        }
            
        // Даем команду пулу: "Выплюни токены!"
        IPool(factory.getPair(input, output)).swap(amount0Out, amount1Out, recipient);
      }
    }

    // Помощник: считает выходные суммы для всей цепочки обмена
    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn; // Начальная сумма — то, что ты вводишь

        for (uint256 i; i < path.length - 1; i++) {
            // 1. Находим пул для текущей пары в пути
            address pair = factory.getPair(path[i], path[i+1]);
            require(pair != address(0), "PAIR_NOT_FOUND");

            // 2. Берем резервы этого пула
            (uint112 reserve0, uint112 reserve1, ) = IPool(pair).getReserves();
            
            // 3. Сортируем, чтобы понять, где reserveIn, а где reserveOut
            (address token0, ) = _sortTokens(path[i], path[i+1]);
            (uint256 reserveIn, uint256 reserveOut) = path[i] == token0 
                ? (uint256(reserve0), uint256(reserve1)) 
                : (uint256(reserve1), uint256(reserve0));

            // 4. Считаем выход для этого шага через нашу первую функцию
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // Расчет: сколько получим на выходе (amountOut) при известном входе (amountIn)
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
      require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
      require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
     
      // 1. Берем комиссию 0.3% (умножаем на 997 из 1000)
      uint256 amountInWithFee = amountIn * 997;
    
      // 2. Формула: (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee)
      uint256 numerator = amountInWithFee * reserveOut;
      uint256 denominator = (reserveIn * 1000) + amountInWithFee;
    
      amountOut = numerator / denominator;
    }


    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
     public pure returns (uint256 amountIn) {
        // 1. Проверки: нельзя купить больше, чем есть в пуле
        require(amountOut > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        require(amountOut < reserveOut, "INSUFFICIENT_RESERVE_OUT");

        // 2. Считаем числитель (сколько нужно резерва на покупку)
        uint256 numerator = reserveIn * amountOut * 1000;
        
        // 3. Считаем знаменатель (остаток резерва с учетом комиссии)
        uint256 denominator = (reserveOut - amountOut) * 997;
        
        // 4. Итоговая сумма + 1 для округления вверх
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
     public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        
        // Ставим желаемую сумму в самый конец массива
        amounts[amounts.length - 1] = amountOut;

        // Идем циклом НАЗАД от последнего пула к первому
        for (uint256 i = path.length - 1; i > 0; i--) {
            address pair = factory.getPair(path[i-1], path[i]);
            (uint112 reserve0, uint112 reserve1, ) = IPool(pair).getReserves();
            
            (address token0, ) = _sortTokens(path[i-1], path[i]);
            (uint256 reserveIn, uint256 reserveOut) = path[i-1] == token0 
                ? (uint256(reserve0), uint256(reserve1)) 
                : (uint256(reserve1), uint256(reserve0));

            // Считаем сумму для предыдущего шага
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
}

    // MAIN: addLiquidity for ERC20 pair (no ETH handling here)
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity){
        require(block.timestamp <= deadline, "EXPIRED");

        // 2. Вызываем наш "калькулятор", который сделает всю грязную работу
        // Он и пару создаст, и резервы проверит, и пропорции высчитает
        (amountA, amountB) = _calculateLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        // 3. Получаем адрес пары (теперь мы уверены, что она существует)
        // _calaulateLiquidity создаст нам пару если его нет
        address pair = factory.getPair(tokenA, tokenB);

        // 4. Переводим токены в Пул
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);

        // 5. Минтим LP-токены пользователю
        liquidity = IPool(pair).mint(to);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline // Добавим дедлайн для безопасности, как мы обсуждали!
    ) external returns (uint256[] memory amounts) {
        // Проверка времени
        require(block.timestamp <= deadline, "EXPIRED");

        // 1. Считаем всю цепочку
        amounts = getAmountsOut(amountIn, path);
        
        // 2. Проверяем, что итоговая сумма не меньше минимума пользователя
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        // 3. Переводим токены от пользователя в ПЕРВЫЙ пул цепочки
        address firstPair = factory.getPair(path[0], path[1]);
        IERC20(path[0]).safeTransferFrom(msg.sender, firstPair, amounts[0]);

        // 4. Запускаем рекурсивный или цикличный обмен по всем пулам
        _swap(amounts, path, to);
    }

      function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,    // Сколько LP-токенов ты хочешь сжечь
        uint256 amountAMin,   // Минимум Токена А, который хочешь получить
        uint256 amountBMin,   // Минимум Токена Б, который хочешь получить
        address to,           // Кому отправить токены
        uint256 deadline      // Срок годности транзакции
    ) public returns (uint256 amountA, uint256 amountB) {
        // 0. Проверка дедлайна
        require(block.timestamp <= deadline, "EXPIRED");

        // 1. Находим адрес пула через фабрику
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");

        // 2. Отправляем LP-токены от пользователя В ПУЛ
        // Перед этим пользователь должен сделать approve(router, liquidity) для LP-токена
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);

        // 3. Вызываем функцию burn в самом Пуле
        // Пул сожжет LP-токены, которые мы ему только что прислали, 
        // и отправит активы на адрес "to"
        (uint256 amount0, uint256 amount1) = IPool(pair).burn(to);

        // 4. Сортируем токены, чтобы понять, какой объем относится к A, а какой к B
        (address token0, ) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 
            ? (amount0, amount1) 
            : (amount1, amount0);

        // 5. Защита от проскальзывания (Slippage)
        // Если из-за изменения цены ты получил меньше, чем рассчитывал — отмена
        require(amountA >= amountAMin, "INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "INSUFFICIENT_B_AMOUNT");
    }

     function addLiquidityETH(
        address token, // часть пары, например USDC
        uint256 amountTokenDesired, // сколько этого токена мы хотим положить
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(block.timestamp <= deadline, "EXPIRED");

        // 1. Считаем, сколько токена и ETH реально нужно положить (математика та же)
        // Мы вызываем внутреннюю логику расчета, которую использовали в обычном addLiquidity
        (amountToken, amountETH) = _calculateLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value, // Твой присланный ETH
            amountTokenMin,
            amountETHMin
        );

        address pair = factory.getPair(token, WETH);

        // 2. Забираем токены у пользователя и отправляем в Пул
        IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);

        // 3. Оборачиваем присланный ETH в WETH
        IWETH(WETH).deposit{value: amountETH}();

        // 4. Отправляем полученный WETH в Пул
        assert(IWETH(WETH).transfer(pair, amountETH));

        require(to != address(0), "INVALID_TO");
        // 5. Выпускаем LP-токены (как обычно)
        liquidity = IPool(pair).mint(to);

        // 6. Возвращаем "сдачу", если прислали больше ETH, чем нужно
        if (msg.value > amountETH) {
            // Переводим лишний ETH обратно пользователю
            (bool success, ) = msg.sender.call{value: msg.value - amountETH}("");
            require(success, "ETH_TRANSFER_FAILED");
        }
    }

     function removeLiquidityETH(
        address token, // токен в паре с ETH, например DAI
        uint256 liquidity, // сколько LP токенов мы хотим сжечь
        uint256 amountTokenMin, // сколько токенов минимум мы хотим получить
        uint256 amountETHMin, // минимум ETH которых мы хотим получить
        address to, // куда переводить токены
        uint256 deadline // дедлайн, срок годность транзакции
    ) public returns (uint256 amountToken, uint256 amountETH) {
        require(block.timestamp <= deadline, "EXPIRED");

        // 1. Сначала делаем стандартный забор ликвидности, 
        // но получателем (to) указываем САМ РОУТЕР (address(this))
        // Роутер заберет токены у Пула на себя, чтобы потом их обработать.
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH, // Мы знаем, что вторая часть пары - это WETH
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this), // Получаем токены на баланс Роутера
            deadline
        );

        // 2. Отправляем обычный токен (например, DAI) пользователю
        IERC20(token).safeTransfer(to, amountToken);

        // 3. А теперь магия с WETH:
        // Роутер говорит контракту WETH: "Забери свои фантики и отдай мне настоящий эфир"
        IWETH(WETH).withdraw(amountETH);

        // 4. Теперь на балансе Роутера появился настоящий ETH. 
        // Отправляем его пользователю "to"
        (bool success, ) = to.call{value: amountETH}("");
        require(success, "ETH_TRANSFER_FAILED");
    }

    // свопаем ETH на токены, типо у меня есть 1 ETH, сколько токенов я получу за него 
     function swapExactETHForTokens(
        uint256 amountOutMin,    // Минимум токенов на выходе
        address[] calldata path, // Путь, должен начинаться с WETH
        address to,              // Кому отправить купленное
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        require(path[0] == WETH, "INVALID_PATH");
        
        // Считаем сколько получим (на входе msg.value - присланный ETH)
        amounts = getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        // Оборачиваем присланный ETH
        IWETH(WETH).deposit{value: amounts[0]}();
        
        // Отправляем WETH в первый пул
        address pair = factory.getPair(path[0], path[1]);
        assert(IWETH(WETH).transfer(pair, amounts[0]));

        // Делаем обмен
        _swap(amounts, path, to);
    }

    // свопаем ETH на токены, типа мне нужно 2000 usdc, сколько ETH мне надо отдать
    function swapETHForExactTokens(
        uint256 amountOut,       // Сколько токенов хотим купить (ровно)
        address[] calldata path, // Путь [WETH, Token]
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        require(path[0] == WETH, "INVALID_PATH");
        
        // Считаем сколько ETH нужно для покупки amountOut токенов
        amounts = getAmountsIn(amountOut, path);
        
        // Проверяем, хватит ли того, что прислал пользователь
        require(amounts[0] <= msg.value, "EXCESSIVE_INPUT_AMOUNT");

        // Оборачиваем только НУЖНУЮ сумму ETH
        IWETH(WETH).deposit{value: amounts[0]}();
        
        // Отправляем WETH в первый пул
        address pair = factory.getPair(path[0], path[1]);
        assert(IWETH(WETH).transfer(pair, amounts[0]));

        // Делаем обмен
        _swap(amounts, path, to);

        // ВОЗВРАЩАЕМ СДАЧУ (если прислали больше, чем нужно по расчету)
        if (msg.value > amounts[0]) {
            (bool success, ) = msg.sender.call{value: msg.value - amounts[0]}("");
            require(success, "ETH_TRANSFER_FAILED");
        }
    }

    // обмен токенов на ETH, типа у меня есть 1000 usdc, сколько ETH ты мне дашь
    function swapExactTokensForETH(
        uint256 amountIn,        // Сколько токенов отдаем
        uint256 amountOutMin,    // Минимум ETH на выходе
        address[] calldata path, // Путь [Token, ..., WETH]
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "INVALID_PATH");
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        // 1. Отдаем токены в первый пул
        IERC20(path[0]).safeTransferFrom(
            msg.sender, 
            factory.getPair(path[0], path[1]), 
            amounts[0]
        );

        // 2. Делаем обмен, но ПОЛУЧАТЕЛЬ — этот контракт (address(this))
        _swap(amounts, path, address(this));

        // 3. Распаковываем WETH в ETH
        uint256 amountETH = amounts[amounts.length - 1];
        IWETH(WETH).withdraw(amountETH);

        // 4. Отправляем ETH пользователю
        (bool success, ) = to.call{value: amountETH}("");
        require(success, "ETH_TRANSFER_FAILED");
    }

    function swapTokensForExactETH(
        uint256 amountOut,       // Сколько ETH хотим получить (точно)
        uint256 amountInMax,     // Максимум токенов, которые готовы отдать
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "INVALID_PATH");
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");

        // 1. Отдаем токены в первый пул
        IERC20(path[0]).safeTransferFrom(
            msg.sender, 
            factory.getPair(path[0], path[1]), 
            amounts[0]
        );

        // 2. Обмен до Роутера
        _swap(amounts, path, address(this));

        // 3. Распаковка
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);

        // 4. Отправка ETH
        (bool success, ) = to.call{value: amounts[amounts.length - 1]}("");
        require(success, "ETH_TRANSFER_FAILED");
    }
}
