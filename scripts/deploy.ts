import pkg from "hardhat";
const { ethers } = pkg;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // 1. Factory
  const Factory = await ethers.getContractFactory("Factory");
  const factory = await Factory.deploy();
  await factory.waitForDeployment();
  console.log("Factory address:", await factory.getAddress());

  // 2. WETH (на Sepolia лучше задеплоить свой для тестов)
  const WETH = await ethers.getContractFactory("WETH9");
  const weth = await WETH.deploy();
  await weth.waitForDeployment();
  console.log("WETH address:", await weth.getAddress());

  // 3. Router
  const Router = await ethers.getContractFactory("Router");
  const router = await Router.deploy(await factory.getAddress(), await weth.getAddress());
  await router.waitForDeployment();
  console.log("Router address:", await router.getAddress());

  // 4. Test Token (чтобы было с чем создать пару)
  const Token = await ethers.getContractFactory("ERC20Mock");
  const token = await Token.deploy("TwilightToken", "TWLT", deployer.address, ethers.parseEther("1000000"));
  await token.waitForDeployment();
  console.log("Test Token (TWLT) address:", await token.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});