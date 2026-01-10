import pkg from 'hardhat';
const { ethers } = pkg;
import { expect } from "chai";

// test for mint
describe("Pool: Mint", function () {

  it("Should mint LP tokens for the first liquidity provider", async function () {
    const [owner] = await ethers.getSigners();

    // 1. Деплоим два мок-токена (нам нужны их адреса)
    const Token = await ethers.getContractFactory("ERC20Mock");
    const t0 = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("100"));
    const t1 = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("100"));

    // 2. Деплоим Пул напрямую
    const Pool = await ethers.getContractFactory("Pool");
    const pool = await Pool.deploy(t0.target, t1.target);

    // 3. Имитируем работу Роутера: ПЕРЕДАЕМ токены в пул
    const amount0 = ethers.parseEther("1"); // 1 токен
    const amount1 = ethers.parseEther("4"); // 4 токена
    await t0.transfer(pool.target, amount0);
    await t1.transfer(pool.target, amount1);

    // 4. Вызываем mint
    // Формула в коде: sqrt(1 * 4) = 2. 
    // В единицах wei это будет sqrt(1e18 * 4e18) = 2e18.
    // Вычитаем MINIMUM_LIQUIDITY (1000).
    await pool.mint(owner.address);

    // 5. ПРОВЕРКА: Получил ли пользователь свои LP-токены?
    const expectedLP = ethers.parseEther("2") - 1000n; 
    expect(await pool.balanceOf(owner.address)).to.equal(expectedLP);

    // 6. ПРОВЕРКА: Обновились ли резервы в пуле?
    const [res0, res1] = await pool.getReserves();
    expect(res0).to.equal(amount0);
    expect(res1).to.equal(amount1);
  });

  // test for burn
   it("it should burn LP tokens and transfer token0/token1 to user", async function(){
      const[owner] = await ethers.getSigners();
      // Берем токены для деплоя
      const Token = await ethers.getContractFactory("ERC20Mock");
      const t0 = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("100"));
      const t1 = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("100"));

      // деплоим пул
      const Pool = await ethers.getContractFactory("Pool");
      const pool = await Pool.deploy(t0.target, t1.target);

        // 3. Имитируем работу Роутера: ПЕРЕДАЕМ токены в пул
      const amount0 = ethers.parseEther("1"); // 1 токен
      const amount1 = ethers.parseEther("4"); // 4 токена
      await t0.transfer(pool.target, amount0);
      await t1.transfer(pool.target, amount1);

          // 4. Вызываем mint
       await pool.mint(owner.address);

       // ТЕПЕРЬ получаем реальное количество LP токенов, которые у нас есть
      const amountLP = await pool.balanceOf(owner.address);

      // берем баланс токенов у owner для дальнейшего сравнения
      const balanceT0Before = await t0.balanceOf(owner.address);
      const balanceT1Before = await t1.balanceOf(owner.address);

      // отправляем LP токены в пул
      await pool.transfer(pool.target, amountLP);

      // сжигаем токены и передаем адрес юзера куда надо отправить токены пары
      await pool.burn(owner.address);

      const[reserve0, reserve1] = await pool.getReserves();

      // проверяем счет юзера
      expect(await pool.balanceOf(owner.address)).to.equal(0n);

      // проверяем резервы
      expect(reserve0 > 0).to.equal(true);
      expect(reserve1 > 0).to.equal(true);

        // проверяем баланс пользователя
      const balanceT0After = await t0.balanceOf(owner.address);
      const balanceT1After = await t1.balanceOf(owner.address);

      expect(balanceT0After).to.be.gt(balanceT0Before);
      expect(balanceT1After).to.be.gt(balanceT1Before);

      // Считаем, сколько примерно нам должно вернуться.
      // Мы вложили 1 токен (10^18 wei). 
      // Потеря из-за MINIMUM_LIQUIDITY (1000) будет ничтожной, 
      // но она есть.

      const expectedT0 = amount0; // 1.0 T0
      const expectedT1 = amount1; // 4.0 T1

      // Проверяем баланс после Burn. 
      // Он должен быть почти равен тому, что мы вложили изначально (100 токенов), 
      // потому что мы сначала вложили 1, а потом его же и забрали.
      const finalT0 = await t0.balanceOf(owner.address);
      const finalT1 = await t1.balanceOf(owner.address);

      // Вместо того чтобы мучаться с формулами, проверим, что 
      // итоговый баланс owner'а стал ПРИМЕРНО 100 токенов (как и было в самом начале).
      // Погрешность будет мизерная (те самые 1000 wei).

      // closeTo значит "примерно равно" с допустимой разницей в 2000 wei
      expect(finalT0).to.be.closeTo(ethers.parseEther("100"), 2000n);
      expect(finalT1).to.be.closeTo(ethers.parseEther("100"), 2000n);

      // 3. Проверяем резервы в пуле.
      // Там должно остаться ровно столько, сколько мы НЕ смогли забрать
      const [res0, res1] = await pool.getReserves();
      expect(res0).to.be.gt(0n);
      expect(res1).to.be.gt(0n);
   })

   // swap test
   it("must swap pair tokens correctly", async function(){
      const[owner] = await ethers.getSigners();
      // Берем токены для деплоя
      const Token = await ethers.getContractFactory("ERC20Mock");
      const t0 = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("100"));
      const t1 = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("100"));

      // деплоим пул
      const Pool = await ethers.getContractFactory("Pool");
      const pool = await Pool.deploy(t0.target, t1.target);

      const amount0 = ethers.parseEther("10"); // 10 токенов
      const amount1 = ethers.parseEther("20"); // 20 токенов

      await t0.transfer(pool.target, amount0);
      await t1.transfer(pool.target, amount1);
      await pool.mint(owner.address)

      const balanceT1Before = await t1.balanceOf(owner.address);

      // отправляем на адрес пула 1 токен для свопа
      await t0.transfer(pool.target, ethers.parseEther("1"));

      // вызываем своп
      const amountOut = ethers.parseEther("1.5")
      await pool.swap(0, amountOut, owner.address)

      const balanceT1After = await t1.balanceOf(owner.address);

      expect(balanceT1After).to.equal(balanceT1Before + amountOut);

      const [reserve0, reserve1] = await pool.getReserves();
      expect(reserve0).to.equal(ethers.parseEther("11"));
      expect(reserve1).to.equal(ethers.parseEther("18.5"));
   })

   // revert
   it("must revert if user want more than pool has", async function(){
     const[owner] = await ethers.getSigners();
      // Берем токены для деплоя
      const Token = await ethers.getContractFactory("ERC20Mock");
      const t0 = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("100"));
      const t1 = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("100"));

      // деплоим пул
      const Pool = await ethers.getContractFactory("Pool");
      const pool = await Pool.deploy(t0.target, t1.target);

      await t0.transfer(pool.target, ethers.parseEther("10"));
      await t1.transfer(pool.target, ethers.parseEther("10"));
      await pool.mint(owner.address)

      await t0.transfer(pool.target, ethers.parseEther("20"));

      await expect(
         pool.swap(0, ethers.parseEther("20"), owner.address)
      ).to.be.revertedWith("reserve must be bigger than amount out");

   })

  //  // revert
   it("must revert if user wanna transfer to zero address", async function(){
     const[owner] = await ethers.getSigners();
      // Берем токены для деплоя
      const Token = await ethers.getContractFactory("ERC20Mock");
      const t0 = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("100"));
      const t1 = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("100"));

      // деплоим пул
      const Pool = await ethers.getContractFactory("Pool");
      const pool = await Pool.deploy(t0.target, t1.target);

      await t0.transfer(pool.target, ethers.parseEther("10"));
      await t1.transfer(pool.target, ethers.parseEther("10"));
      await pool.mint(owner.address)

      await t0.transfer(pool.target, ethers.parseEther("5"));

      await expect(
         pool.swap(0, ethers.parseEther("5"), ethers.ZeroAddress)
      ).to.be.revertedWith("incorrect address");
   })

  //  // revert
   it("must revert if user wanna transfer to token pool address", async function(){
     const[owner] = await ethers.getSigners();
      // Берем токены для деплоя
      const Token = await ethers.getContractFactory("ERC20Mock");
      const t0 = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("100"));
      const t1 = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("100"));

      // деплоим пул
      const Pool = await ethers.getContractFactory("Pool");
      const pool = await Pool.deploy(t0.target, t1.target);

      await t0.transfer(pool.target, ethers.parseEther("10"));
      await t1.transfer(pool.target, ethers.parseEther("10"));
      await pool.mint(owner.address)

      await t0.transfer(pool.target, ethers.parseEther("5"));

      await expect(
         pool.swap(0, ethers.parseEther("5"), t1.target)
      ).to.be.revertedWith("to can't be token0 or token1 in swap");
   })



});