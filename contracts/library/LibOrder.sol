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
    struct OrderInfo {
        Order order;
        OrderKey next;
    }
    struct OrderQueue {
        Orderkey head;
        OrderKey tail;
    }


    OrderKey public constant ORDERKEY_SENTINEL = OrderKey.wrap(0x0);

    
    function hash(Order memory order) internal pure returns (OrderKey) {
        return OrderKey.wrap(
            keccak256(
                abi.encodePacked(
                    order.side,
                    order.saleKind,
                    order.maker,
                    order.nft.collection,
                    order.nft.tokenId,
                    order.nft.amount,
                    Price.unwrap(order.price),
                    order.expiry,
                    order.salt
                )
            )
        );
    }
}
