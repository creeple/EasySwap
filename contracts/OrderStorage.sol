// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;


import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./library/LibOrder.sol";
import {RedBlackTreeLibrary, Price} from "./library/RedBlackTreeLibrary.sol";

contract OrderStorage is Initializable{

    function __OrderStorage_init() internal onlyInitializing {}

    function __OrderStorage_init_unchained() internal onlyInitializing {}

    uint256 private constant CANCELLED = type(uint256).max;
    
    mapping(OrderKey => uint256)  public orderStatus;
}
