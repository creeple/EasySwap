// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import "./library/LibOrder.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {LibSafeTransferUpgradeable} from "./library/LibSafeTransferUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {Price} from "./library/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./library/LibOrder.sol";
contract EasySwapOrderBook is Initializable, ContextUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, OrderStorage, ProtocolManager, OrderValidator {

    using LibSafeTransferUpgradeable for address;
//    using LibSafeTransferUpgradeable for IERC721;
    function initialize(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP712Name,
        string memory EIP712Version
    ) public initializer {
        __EasySwapOrderBook_init(
            newProtocolShare,
            newVault,
            EIP712Name,
            EIP712Version
        );
    }

    function __EasySwapOrderBook_init(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing {
        __EasySwapOrderBook_init_unchained(
            newProtocolShare,
            newVault,
            EIP712Name,
            EIP712Version
        );
    }

    function __EasySwapOrderBook_init_unchained(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing {
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
        __Pausable_init();
        __OrderStorage_init();
        __ProtocolManager_init(newProtocolShare);
        __OrderValidator_init(EIP712Name, EIP712Version);

        setVault(newVault);
    }

    address private _vault;

    function setVault(address newVault) public onlyOwner {
        require(newVault != address(0), "HD: zero address");
        _vault = newVault;
    }

    //创建批量订单
    function makeOrders(LibOrder.Order[] calldata newOrders) external payable whenNotPaused nonReentrant returns(OrderKey[] memory orderKeys){
        uint256 orderAmount = newOrders.length;
        orderKeys = new OrderKey[](orderAmount);
        //定义ETHAmount，如果是买bid 行为，记录需要多少ETH,计算用户eth是否充足
        uint128 ETHAmount;
        for(uint256 i = 0;i<orderAmount;++i){
            uint128 buyPrice;
            if(newOrders[i].side == LibOrder.Side.Bid){
                buyPrice = Price.unwrap(newOrders[i].price) * newOrders[i].nft.amount;
            }
            OrderKey orderKey = makeOrdersTry(newOrders[i],buyPrice);
            orderKeys[i] = orderKey;
            //判断订单是否创建成功，如果订单创建成功，则累加ETHAmount
            if(orderKey!= LibOrder.ORDERKEY_SENTINEL()){
                ETHAmount += buyPrice;
            }
        }
        //判断用户余额是否够用
        if(msg.value > ETHAmount){
            _msgSender().safeTransferETH(msg.value - ETHAmount);
        }

    }

    function makeOrdersTry(Order orderInfo,uint128 buyPrice) internal returns(OrderKey orderKey){
        //校验条件
        if(
            orderInfo.maker != _msgSender() && Price.unwrap(orderInfo.price) !=0 &&
            orderInfo.salt !=0 && (orderInfo.expiry > block.timestamp || orderInfo.expiry == 0) &&
            filledAmount[LibOrder.hash(orderInfo)] == 0 && orderStatus[orderInfo] == 0
        )
    }


}
