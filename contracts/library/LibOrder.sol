// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Price} from "./RedBlackTreeLibrary.sol";

type OrderKey is bytes32;

library LibOrder {
    //交易方向
    enum Side {
        List,
        Bid
    }
    enum SaleKind {
        FixedPriceForCollection,
        FixedPriceForItem
    }
    struct Asset {
        uint256 tokenId;
        address collection; //nft合约地址
        uint96 amount;
    }
    struct NFTInfo{
        address collection;
        uint256 tokenId;
    }
    struct Order{
        Side side;
        SaleKind saleKind;
        address maker;//订单发起者
        Asset nft;
        Price price;
        uint64 expiry;
        uint64 salt;
    }
    struct DBOrder {
        Order order;
        OrderKey next;
    }

    OrderKey public constant ORDERKEY_SENTINEL = OrderKey.wrap(0x0);
}
