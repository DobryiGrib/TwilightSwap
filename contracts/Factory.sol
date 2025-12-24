// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Pool.sol";

contract Factory is Ownable{

    constructor() {}
   event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    mapping (address => mapping(address => address)) public getPair;
    address[] public allPairs;

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1){
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0) && token1 != address(0), "ZERO_ADDRESS");
    }

    function allPairsLength() external view returns (uint256) {
    return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) public returns (address pair) {
        address token0;
        address token1;
        require(getPair[tokenA][tokenB] == address(0), "PAIR_EXISTS");
        (token0, token1) = sortTokens(tokenA, tokenB);
        pair = address(new Pool(token0, token1));
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
       emit PairCreated(token0, token1, pair, allPairs.length);
       return pair;
    }
}