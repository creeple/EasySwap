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


    function getOrders(address collection, uint256 tokenId, LibOrder.Side side, LibOrder.SaleKind saleKind, uint256 count, Price price, OrderKey firstOrderKey) external view returns (LibOrder.Order[] memory resultOrders, OrderKey nextOrderKey)
    {
        resultOrders = new LibOrder.Order[](count);
        if (RedBlackTreeLibrary.isEmpty(price)) {
            price = getBestPrice(collection, side);
        } else {
            if (LibOrder.isSentinel(firstOrderKey)) {
                price = getNextBestPrice(collection, side, price);
            }
        }
        uint256 i;
        while (RedBlackTreeLibrary.isNotEmpty(price) && i < count) {
            LibOrder.OrderQueue memory orderQueue = priceOrders[collection][side][price];
            OrderKey orderKey = orderQueue.head;
            if (LibOrder.isNotSentinel(firstOrderKey)) {
                while (LibOrder.isNotSentinel(orderKey) && OrderKey.unwrap(orderKey) != OrderKey.unwrap(firstOrderKey)) {
                    LibOrder.OrderInfo memory order = orders[orderKey];
                    orderKey = order.next;
                }
                firstOrderKey = LibOrder.ORDERKEY_SENTINEL;
            }
            while (LibOrder.isNotSentinel(orderKey) && i < count) {
                LibOrder.OrderInfo memory dbOrder = orders[orderKey];
                orderKey = dbOrder.next;
                if ((dbOrder.order.expiry != 0 && dbOrder.order.expiry < block.timestamp)) {
                    continue;
                }
                if ((side == LibOrder.Side.Bid) && (saleKind == LibOrder.SaleKind.FixedPriceForCollection)) {
                    if ((dbOrder.order.side == LibOrder.Side.Bid) && (dbOrder.order.saleKind == LibOrder.SaleKind.FixedPriceForItem)) {
                        continue;
                    }
                }

                if ((side == LibOrder.Side.Bid) && (saleKind == LibOrder.SaleKind.FixedPriceForItem)) {
                    if ((dbOrder.order.side == LibOrder.Side.Bid) && (dbOrder.order.saleKind == LibOrder.SaleKind.FixedPriceForItem) && (tokenId != dbOrder.order.nft.tokenId)) {
                        continue;
                    }
                }
                resultOrders[i] = dbOrder.order;
                nextOrderKey = dbOrder.next;
                i = i+1;
            }
            price = getNextBestPrice(collection, side, price);
        }
    }

    function getBestOrder(
        address collection,
        uint256 tokenId,
        LibOrder.Side side,
        LibOrder.SaleKind saleKind
    ) external view returns (LibOrder.Order memory orderResult) {
        Price price = getBestPrice(collection, side);
        while (RedBlackTreeLibrary.isNotEmpty(price)) {
            LibOrder.OrderQueue memory orderQueue = priceOrders[collection][side][price];
            OrderKey orderKey = orderQueue.head;
            while (LibOrder.isNotSentinel(orderKey)) {
                LibOrder.OrderInfo memory dbOrder = orders[orderKey];
                if ((side == LibOrder.Side.Bid) && (saleKind == LibOrder.SaleKind.FixedPriceForItem)) {
                    if ((dbOrder.order.side == LibOrder.Side.Bid) && (dbOrder.order.saleKind == LibOrder.SaleKind.FixedPriceForItem) && (tokenId != dbOrder.order.nft.tokenId)) {
                        orderKey = dbOrder.next;
                        continue;
                    }
                }
                if ((side == LibOrder.Side.Bid) && (saleKind == LibOrder.SaleKind.FixedPriceForCollection)) {
                    if ((dbOrder.order.side == LibOrder.Side.Bid) && (dbOrder.order.saleKind == LibOrder.SaleKind.FixedPriceForItem)) {
                        orderKey = dbOrder.next;
                        continue;
                    }
                }

                if ((dbOrder.order.expiry == 0 || dbOrder.order.expiry > block.timestamp)) {
                    orderResult = dbOrder.order;
                    break;
                }
                orderKey = dbOrder.next;
            }
            if (Price.unwrap(orderResult.price) > 0) {
                break;
            }
            price = getNextBestPrice(collection, side, price);
        }
    }
    function getBestPrice(
        address collection,
        LibOrder.Side side
    ) public view returns (Price price) {
        price = (side == LibOrder.Side.Bid)
            ? priceTrees[collection][side].last()
            : priceTrees[collection][side].first();
    }

    function getNextBestPrice(
        address collection,
        LibOrder.Side side,
        Price price
    ) public view returns (Price nextBestPrice) {
        if (RedBlackTreeLibrary.isEmpty(price)) {
            nextBestPrice = (side == LibOrder.Side.Bid)
                ? priceTrees[collection][side].last()
                : priceTrees[collection][side].first();
        } else {
            nextBestPrice = (side == LibOrder.Side.Bid)
                ? priceTrees[collection][side].prev(price)
                : priceTrees[collection][side].next(price);
        }
    }



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
            LibOrder.OrderInfo memory dbOrder = orders[orderKey];
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
                delete priceOrders[order.nft.collection][order.side][
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

    uint256[50] private __gap;
}
