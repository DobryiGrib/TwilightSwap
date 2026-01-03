import pkg from 'hardhat';
const { ethers } = pkg;
import { expect } from "chai";

describe("Factory", function (){
    
    it("must let us create pair", async function(){
        const [owner] = await ethers.getSigners();
        const Token = await ethers.getContractFactory("ERC20Mock");
        const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("100"));
        const tokenB = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("100"));

        const Factory = await ethers.getContractFactory("Factory");
        const factory = await Factory.deploy();

        await factory.createPair(tokenA.target, tokenB.target);
        const pairAddress = await factory.getPair(tokenA.target, tokenB.target);
        // Проверяем симметрию (что порядок токенов не важен)
        const pairAddressReverse = await factory.getPair(tokenB.target, tokenA.target);

        const firstPair = await factory.allPairs(0);

        expect(pairAddress).to.not.equal(ethers.ZeroAddress);
        expect(pairAddress).to.equal(pairAddressReverse);
        expect(pairAddress).to.equal(firstPair);
    })

    // revert
    it("must revert if user wanna create exist pair", async function(){
        const [owner] = await ethers.getSigners();
        const Token = await ethers.getContractFactory("ERC20Mock");
        const tokenA = await Token.deploy("T0", "T0", owner.address, ethers.parseEther("100"));
        const tokenB = await Token.deploy("T1", "T1", owner.address, ethers.parseEther("100"));

        const Factory = await ethers.getContractFactory("Factory");
        const factory = await Factory.deploy();

        await factory.createPair(tokenA.target, tokenB.target);

      await expect(
             factory.createPair(tokenB.target, tokenA.target)
        ).to.be.revertedWith("PAIR_EXISTS");

    })

});