// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IEasySwapVault} from "./interface/IEasySwapVault.sol";
import {LibOrder,OrderKey} from "./library/LibOrder.sol";
import {LibSafeTransferUpgradeable} from "./library/LibSafeTransferUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
//此合约用于接受和处理用户的nft以及eth转账的资金池合约

contract EasySwapVault is IEasySwapVault,OwnableUpgradeable {

    using LibSafeTransferUpgradeable for address;
    using LibSafeTransferUpgradeable for IERC721;
    //设置可以调用此资金池方法权限的地址，一般来说只有业务逻辑合约可以调用此资金池合约
    address public orderBookAddress;

    //买单的实际余额
    mapping(OrderKey => uint256) public ETHBalance;
    //挂单时，存放tokenId
    mapping(OrderKey => uint256) public NFTBalance;
    //初始化方法，外部调用，只能调用一次
    //因为EasySwapVault继承了OwnableUpgradeable，OwnableUpgradeable继承了ContextUpgradeable
    function initialize() public initializer{
        __Ownable_init(_msgSender());
    }

    function setOrderBookAddress(address newOrderBook) public onlyOwner {
        require(newOrderBook != address(0),"zero address");
        orderBookAddress = newOrderBook;
    }

    modifier onlyOrderBook(){
        require(msg.sender == orderBookAddress,"only orderBook");
        _;
    }

    function balanceOf(OrderKey orderKey) external view returns(uint ETHAmount,uint256 tokenId){
        ETHAmount = ETHBalance[orderKey];
        tokenId = NFTBalance[orderKey];
    }
    function depositETH(OrderKey orderKey,uint256 amount) external payable onlyOrderBook{
        require(msg.value>=amount,"amount not enough");
        ETHBalance[orderKey] += amount;
    }

    function withdrawETH(Orderkey orderKey,uint256 amount, address to) external onlyOrderBook{
        require(ETHBalance[orderKey] >= amount,"amount not enough");
        to.safeTransferETH(amount);
        ETHBalance[orderKey] -= amount;
    }

    function depositNFT(OrderKey orderKey, address from, address collection,uint256 tokenId) external onlyOrderBook{
        IERC721(collection).safeTransferNFT(from,address(this),tokenId);
        NFTBalance[orderKey] = [tokenId];
    }
    function withdrawNFT(OrderKey orderKey,address to,address collection,uint256 tokenId) external onlyOrderBook{
        require(NFTBalance[orderKey] == tokenId, "HV: not match tokenId");
        IERC721(collection).safeTransferNFT(address(this),to,tokenId);
        delete NFTBalance[orderKey];
    }
    function editETH(OrderKey oldOrderKey, OrderKey newOrderKey, uint256 oldETHAmount, uint256 newETHAmount, address to) external payable onlyOrderBook {
        ETHBalance[oldOrderKey] = 0;
        if (oldETHAmount > newETHAmount) {
            ETHBalance[newOrderKey] = newETHAmount;
            to.safeTransferETH(oldETHAmount - newETHAmount);
        } else if (oldETHAmount < newETHAmount) {
            require(
                msg.value >= newETHAmount - oldETHAmount,
                "HV: not match newETHAmount"
            );
            ETHBalance[newOrderKey] = msg.value + oldETHAmount;
        } else {
            ETHBalance[newOrderKey] = oldETHAmount;
        }
    }

    function editNFT(OrderKey oldOrderKey, OrderKey newOrderKey) external onlyOrderBook {
        NFTBalance[newOrderKey] = NFTBalance[oldOrderKey];
        delete NFTBalance[oldOrderKey];
    }

}
