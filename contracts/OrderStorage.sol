// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;


import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {LibOrder,OrderKey} from "./library/LibOrder.sol";
import {RedBlackTreeLibrary, Price} from "./library/RedBlackTreeLibrary.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
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
    mapping(address =>mapping(LibOrder.Side => RedBlackTreeLibrary.Tree)) public priceTree;

    //存放相同价格相同交易方向的NFT的第一笔产生的交易价格，和最新一笔的交易信息orderKey
    mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue))) public priceOrder;

    function addOrder(LibOrder.Order memory order) internal{

    }
}
