// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;


import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {LibOrder,OrderKey} from "./library/LibOrder.sol";
import {RedBlackTreeLibrary, Price} from "./library/RedBlackTreeLibrary.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

error DuplicateOrder(OrderKey orderKey);
contract OrderStorage is Initializable{

    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;

    function __OrderStorage_init(string memory EIP712Name, string memory EIP712Version) internal onlyInitializing {
        __EIP712_init(EIP712Name, EIP712Version);
        __OrderStorage_init_unchained();
    }

    function __OrderStorage_init_unchained() internal onlyInitializing {}

    uint256 private constant CANCELLED = type(uint256).max;

    //存放订单状态
    mapping(OrderKey => uint256)  public orderStatus;

    //存放订单信息
    mapping(OrderKey => LibOrder.OrderInfo) public orders;

    //存放同一个NFT代币类型的卖出，买入价格信息
    mapping(address =>mapping(LibOrder.Side => RedBlackTreeLibrary.Tree)) public priceTrees;

    //存放相同价格相同交易方向的NFT的第一笔产生的交易价格，和最新一笔的交易信息orderKey
    mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue))) public priceOrders;

    function addOrder(LibOrder.Order memory order) internal{
        OrderKey orderKey = LibOrder.hash(order);
        if(orders[orderKey].order.maker != address(0)){
            revert DuplicateOrder(orderKey);
        }
        //获取价格信息放入价格树
        RedBlackTreeLibrary.Tree storage priceTree = priceTrees[order.nft.collection][order.side];
        if(!priceTree.exists(order.price)){
            priceTree.insert(order.price);
        }
        //获取具有相同价格的订单队列信息（订单信息中存放第一个订单的orderKey和最后一个订单的orderKey）
        LibOrder.OrderQueue storage orderQueue = priceOrders[order.nft.collection][order.side][order.price];
        //判断这个队列是否尚未初始化
        if(orderQueue.head == LibOrder.ORDERKEY_SENTINEL()){
            orderQueue.head = orderKey;
            orderQueue.tail = orderKey;
        }else{
            orders[orderQueue.tail].next = orderKey;
            orderQueue.tail = orderKey;
            orders[orderKey] = LibOrder.OrderInfo(order,LibOrder.ORDERKEY_SENTINEL());
        }

    }
    function cancelOrder(LibOrder.Order order) internal{
        LibOrder.OrderQueue storage orderQueue = priceOrders[order.nft.collection][order.side][order.price];
        OrderKey orderKey = orderQueue.head;
        OrderKey prevOrderKey;
        bool found;
        while (LibOrder.isNotSentinel(orderKey) && !found) {
            LibOrder.DBOrder memory dbOrder = orders[orderKey];
            if (
                (dbOrder.order.maker == order.maker) && (dbOrder.order.saleKind == order.saleKind) &&(dbOrder.order.expiry == order.expiry) && (dbOrder.order.salt == order.salt) && (dbOrder.order.nft.tokenId == order.nft.tokenId) && (dbOrder.order.nft.amount == order.nft.amount)
            ) {
                OrderKey temp = orderKey;
                // emit OrderRemoved(order.nft.collection, orderKey, order.maker, order.side, order.price, order.nft, block.timestamp);
                if (
                    OrderKey.unwrap(orderQueue.head) == OrderKey.unwrap(orderKey)
                ) {
                    orderQueue.head = dbOrder.next;
                } else {
                    orders[prevOrderKey].next = dbOrder.next;
                }
                if (
                    OrderKey.unwrap(orderQueue.tail) ==
                    OrderKey.unwrap(orderKey)
                ) {
                    orderQueue.tail = prevOrderKey;
                }
                prevOrderKey = orderKey;
                orderKey = dbOrder.next;
                delete orders[temp];
                found = true;
            } else {
                prevOrderKey = orderKey;
                orderKey = dbOrder.next;
            }
        }
        if (found) {
            if (LibOrder.isSentinel(orderQueue.head)) {
                delete orderQueues[order.nft.collection][order.side][
                order.price
                ];
                RedBlackTreeLibrary.Tree storage priceTree = priceTrees[
                                    order.nft.collection
                    ][order.side];
                if (priceTree.exists(order.price)) {
                    priceTree.remove(order.price);
                }
            }
        } else {
            revert("Cannot remove missing order");
        }


    }
}
