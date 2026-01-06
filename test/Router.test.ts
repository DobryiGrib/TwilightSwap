import pkg from 'hardhat';
const { ethers } = pkg;
import { expect } from "chai";

describe("Router", function (){
    
    // test #1 addLiquidity
    it("must let user to add liquidity", async function(){
    const [owner] = await ethers.getSigners();
    
    // 1. Деплоим два мок-токена (нам нужны их адреса)
    const Token = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));
    const tokenB = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("1000"));

    // 2. Деплоим factory, router, weth
    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy();
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = await WETH.deploy();
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(factory.target, weth.target);
    const Pool = await ethers.getContractFactory("Pool");
    await tokenA.connect(owner).approve(router.target, ethers.parseEther("500"));
    await tokenB.connect(owner).approve(router.target, ethers.parseEther("500"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 100000);

    // добавляем ликвидность
    await router.addLiquidity(tokenA.target, tokenB.target, ethers.parseEther("10"), ethers.parseEther("10"), 0, 0, owner.address, deadline);

    const pairAddress = await factory.getPair(tokenA.target, tokenB.target);
    expect(pairAddress).to.not.equal(ethers.ZeroAddress);
    expect(await tokenA.balanceOf(owner.address)).to.equal(ethers.parseEther("990"));
    expect(await tokenB.balanceOf(owner.address)).to.equal(ethers.parseEther("990"));
    expect(await tokenA.balanceOf(pairAddress)).to.equal(ethers.parseEther("10"));
    expect(await tokenB.balanceOf(pairAddress)).to.equal(ethers.parseEther("10"));
    const pair = Pool.attach(pairAddress);
    const lpBalance = await pair.balanceOf(owner.address);
    expect(lpBalance).to.be.gt(0);
    })

    // test #2 swap - swapExactTokensForTokens
    it("must let user to swap token/tokens", async function(){
    const [owner] = await ethers.getSigners();
    
    // 1. Деплоим два мок-токена (нам нужны их адреса)
    const Token = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));
    const tokenB = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("1000"));

    // 2. Деплоим factory, router, weth, pool
    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy();
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = await WETH.deploy();
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(factory.target, weth.target);
    const Pool = await ethers.getContractFactory("Pool");
    await tokenA.connect(owner).approve(router.target, ethers.parseEther("500"));
    await tokenB.connect(owner).approve(router.target, ethers.parseEther("500"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 100000);
    
    // добавляем ликвидность 10/10
    await router.addLiquidity(tokenA.target, tokenB.target, ethers.parseEther("10"), ethers.parseEther("10"), 0, 0, owner.address, deadline);
    
    // вызываем swap
    await router.swapExactTokensForTokens(ethers.parseEther("1"), 0, [tokenA.target, tokenB.target], owner.address, deadline);
    const pairAddress = await factory.getPair(tokenA.target, tokenB.target);

    // пишем тесты
    expect(await tokenA.balanceOf(owner.address)).to.equal(ethers.parseEther("989"));
    expect(await tokenB.balanceOf(owner.address)).to.be.closeTo(ethers.parseEther("990.9066"), ethers.parseEther("0.0001"));
    expect(await tokenA.balanceOf(pairAddress)).to.be.closeTo(ethers.parseEther("11"), 2000n);
    expect(await tokenB.balanceOf(pairAddress)).to.lt(ethers.parseEther("10"));
    });

    // test #3 remove liquidity
    it("must let user to remove liquidity", async function(){
    const [owner] = await ethers.getSigners();
    
    // 1. Деплоим два мок-токена (нам нужны их адреса)
    const Token = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));
    const tokenB = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("1000"));

    // 2. Деплоим factory, router, weth, pool
    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy();
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = await WETH.deploy();
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(factory.target, weth.target);
    const Pool = await ethers.getContractFactory("Pool");
    await tokenA.connect(owner).approve(router.target, ethers.parseEther("500"));
    await tokenB.connect(owner).approve(router.target, ethers.parseEther("500"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 100000);
    
    // добавляем ликвидность 10/10 а потом удаляем
    await router.addLiquidity(tokenA.target, tokenB.target, ethers.parseEther("10"), ethers.parseEther("10"), 0, 0, owner.address, deadline);
    const pairAddress = await factory.getPair(tokenA.target, tokenB.target);
    const pair = Pool.attach(pairAddress);
    const lpBalance = await pair.balanceOf(owner.address);
    await pair.approve(router.target, lpBalance);
    await router.removeLiquidity(tokenA.target, tokenB.target, lpBalance, 0, 0, owner.address, deadline);

    // пишем тесты и проверяем
    expect(await pair.balanceOf(owner.address)).to.be.closeTo(ethers.parseEther("0"), 1500n);
    expect(await tokenA.balanceOf(owner.address)).to.be.closeTo(ethers.parseEther("1000"), ethers.parseEther("0.0001"));
    expect(await tokenB.balanceOf(owner.address)).to.be.closeTo(ethers.parseEther("1000"), ethers.parseEther("0.0001"));
    })

    // test #4 add liquidity for ETH  and swap exact ETH fot tokens
    it("must let us to wrap ETH to WETH and  swap exact ETH fot tokens", async function(){
    const [owner] = await ethers.getSigners();
    
    // 1. Деплоим два мок-токена (нам нужны их адреса)
    const Token = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));

    // 2. Деплоим factory, router, weth, pool
    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy();
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = await WETH.deploy();
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(factory.target, weth.target);
    const Pool = await ethers.getContractFactory("Pool");
    await tokenA.connect(owner).approve(router.target, ethers.parseEther("500"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 100000);

    await router.addLiquidityETH(tokenA.target, ethers.parseEther("10"), 0, 0, owner.address, deadline, { value: ethers.parseEther("1") });
    const tokenABalance = await tokenA.balanceOf(owner.address);
    const pairAddress = await factory.getPair(tokenA.target, weth.target);
    const pair = Pool.attach(pairAddress);
    expect(await tokenA.balanceOf(pairAddress)).to.equal(ethers.parseEther("10"));
    expect(await weth.balanceOf(pairAddress)).to.equal(ethers.parseEther("1"));
    expect(await pair.balanceOf(owner.address)).to.be.gt(0);

    await router.swapExactETHForTokens(0, [weth.target, tokenA.target], owner.address, deadline, { value: ethers.parseEther("0.1") });

    expect(await tokenA.balanceOf(owner.address)).to.be.gt(tokenABalance);
    expect(await weth.balanceOf(pairAddress)).to.be.gt(ethers.parseEther("1"));


    })

    // test #5 swap exact tokens for tokens with 3 tokens in 2 pairs
    it("must let us to swap tokenA to tokenB and final to tokenC", async function(){
    const [owner] = await ethers.getSigners();
    
    // 1. Деплоим два мок-токена (нам нужны их адреса)
    const Token = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));
    const tokenB = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));
    const tokenC = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));

    // 2. Деплоим factory, router, weth, pool
    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy();
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = await WETH.deploy();
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(factory.target, weth.target);
    await ethers.getContractFactory("Pool");
    await tokenA.connect(owner).approve(router.target, ethers.parseEther("500"));
    await tokenB.connect(owner).approve(router.target, ethers.parseEther("500"));
    await tokenC.connect(owner).approve(router.target, ethers.parseEther("500"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 100000);

    // создаем 2 пула - tokenA\tokenB - tokenB\tokenC
    await router.addLiquidity(tokenA.target, tokenB.target, ethers.parseEther("10"), ethers.parseEther("10"), 0, 0, owner.address, deadline);
    await router.addLiquidity(tokenB.target, tokenC.target, ethers.parseEther("10"), ethers.parseEther("10"), 0, 0, owner.address, deadline);

    await router.swapExactTokensForTokens(ethers.parseEther("1"), 0, [tokenA.target, tokenB.target, tokenC.target], owner.address, deadline);

    expect(await tokenC.balanceOf(owner.address)).to.be.closeTo(ethers.parseEther("990.82"), ethers.parseEther("0.01"));
    expect(await tokenA.balanceOf(owner.address)).to.be.closeTo(ethers.parseEther("989"), ethers.parseEther("0.001"));
    
    })
    
    // test #6 swap ETH for exact tokens
    it("must let user to swap ETH for exact tokens", async function(){
    const [owner] = await ethers.getSigners();
    // 1. Деплоим два мок-токена (нам нужны их адреса)
    const Token = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));

    // 2. Деплоим factory, router, weth, pool
    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy();
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = await WETH.deploy();
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(factory.target, weth.target);
    const Pool = await ethers.getContractFactory("Pool");
    await tokenA.connect(owner).approve(router.target, ethers.parseEther("1000"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 100000);

    await router.addLiquidityETH(tokenA.target, ethers.parseEther("1000"), 0, 0, owner.address, deadline, { value: ethers.parseEther("1000") });
    const tokenABalance = await tokenA.balanceOf(owner.address);
    const ethBalanceBefore = await ethers.provider.getBalance(owner.address);
    const pairAddress = await factory.getPair(tokenA.target, weth.target);
    const pair = Pool.attach(pairAddress);

    // call swapETHForExactTokens
    await router.swapETHForExactTokens(ethers.parseEther("1"), [weth.target, tokenA.target], owner.address, deadline, {value: ethers.parseEther("2")});
    expect(await tokenA.balanceOf(owner.address)).to.equal(tokenABalance + ethers.parseEther("1"));
    const ethBalanceAfter = await ethers.provider.getBalance(owner.address);
    const diff = ethBalanceBefore - ethBalanceAfter;
    expect(diff).to.be.lt(ethers.parseEther("1.2")); 
    expect(diff).to.be.gt(ethers.parseEther("1.001"));

    })

    // test #7 removeLiquidity for ETH
    it("must let user remove luquidity with ETH", async function(){
    const [owner] = await ethers.getSigners();

    // 1. Деплоим два мок-токена (нам нужны их адреса)
    const Token = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));

    // 2. Деплоим factory, router, weth, pool
    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy();
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = await WETH.deploy();
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(factory.target, weth.target);
    const Pool = await ethers.getContractFactory("Pool");
    await tokenA.connect(owner).approve(router.target, ethers.parseEther("500"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 100000);

    await router.addLiquidityETH(tokenA.target, ethers.parseEther("10"), 0, 0, owner.address, deadline, { value: ethers.parseEther("10") });
    const tokenABalance = await tokenA.balanceOf(owner.address);
    const ethBalanceBefore = await ethers.provider.getBalance(owner.address);
    const pairAddress = await factory.getPair(tokenA.target, weth.target);
    const pair = Pool.attach(pairAddress);
    const lpBalance = await pair.balanceOf(owner.address)
    await pair.approve(router.target, lpBalance);
    await router.removeLiquidityETH(tokenA.target, lpBalance, 0, 0, owner.address, deadline);
    const balanceETHexpect = ethBalanceBefore + ethers.parseEther("10");
    expect(await ethers.provider.getBalance(owner.address)).to.be.closeTo(balanceETHexpect, ethers.parseEther("0.001"));
    expect(await pair.balanceOf(owner.address)).to.equal(0);
    })

    // test #8 fot slippage protection and deadline
    it("must stop slippage protection", async function(){
    const [owner, user1] = await ethers.getSigners();

    // 1. Деплоим два мок-токена (нам нужны их адреса)
    const Token = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("1000"));
    const tokenB = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("1000"));
    const amountToUser = ethers.parseEther("100");
    // Отправляем токены от owner к user1
    await tokenA.transfer(user1.address, amountToUser);
    await tokenB.transfer(user1.address, amountToUser);
    // owner 900, user1 100

    // 2. Деплоим factory, router, weth, pool
    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy();
    const WETH = await ethers.getContractFactory("WETH9");
    const weth = await WETH.deploy();
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(factory.target, weth.target);
    const Pool = await ethers.getContractFactory("Pool");
    await tokenA.connect(owner).approve(router.target, ethers.parseEther("500"));
    await tokenB.connect(owner).approve(router.target, ethers.parseEther("500"));
    await tokenA.connect(user1).approve(router.target, ethers.parseEther("100"));
    await tokenB.connect(user1).approve(router.target, ethers.parseEther("100"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 100000);
    await router.addLiquidity(tokenA.target, tokenB.target, ethers.parseEther("100"), ethers.parseEther("100"), 0, 0, owner.address, deadline);
    // делаем большой своп 10% от пары чтобы сделать проскальзывание
    await router.connect(user1).swapExactTokensForTokens(ethers.parseEther("10"), 0, [tokenA.target, tokenB.target], user1.address, deadline);

    const expiredDeadline = BigInt(Math.floor(Date.now() / 1000) - 60);
    // теперь когда цена изменилась из-за большого свопа, делаем тест на проскальзывание
    await expect(
        router.swapExactTokensForTokens(ethers.parseEther("1"), ethers.parseEther("1"), [tokenA.target, tokenB.target], owner.address, deadline)
    ).to.revertedWith("INSUFFICIENT_OUTPUT_AMOUNT");
    await expect(
         router.swapExactTokensForTokens(ethers.parseEther("1"), 0, [tokenA.target, tokenB.target], owner.address, expiredDeadline)
    ).to.revertedWith("EXPIRED");
    expect(await tokenA.balanceOf(user1.address)).to.equal(ethers.parseEther("90"));
    expect(await tokenB.balanceOf(user1.address)).to.be.gt(ethers.parseEther("108"));

    })

});