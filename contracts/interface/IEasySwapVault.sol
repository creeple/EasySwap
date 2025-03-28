// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {LibOrder, OrderKey} from "../library/LibOrder.sol";

//此接口用于调用EasySwapVault中的方法
interface IEasySwapVault {

    function balanceOf(OrderKey orderKey) external view returns (uint256 ETHAmount, uint256 tokenId);

    function depositETH(OrderKey orderKey, uint256 ETHAmount) external payable;

    function withdrawETH(OrderKey orderKey, uint256 ETHAmount, address to) external;

    function depositNFT(OrderKey orderKey, address from, address collection, uint256 tokenId) external;

    function withdrawNFT(OrderKey orderKey, address to, address collection, uint256 tokenId) external;

}
