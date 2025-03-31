// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import "./library/LibOrder.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {LibSafeTransferUpgradeable} from "./library/LibSafeTransferUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interface/IEasySwapVault.sol";
import {Price} from "./library/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./library/LibOrder.sol";
import "./OrderStorage.sol";

contract EasySwapOrderBook is Initializable, ContextUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, OrderStorage, ProtocolManager, OrderValidator {

    using LibSafeTransferUpgradeable for address;
//    using LibSafeTransferUpgradeable for IERC721;
    function initialize(uint128 newProtocolShare, address newVault, string memory EIP712Name, string memory EIP712Version) public initializer {
        __EasySwapOrderBook_init(
            newProtocolShare,
            newVault,
            EIP712Name,
            EIP712Version
        );
    }

    function __EasySwapOrderBook_init(uint128 newProtocolShare, address newVault, string memory EIP712Name, string memory EIP712Version) internal onlyInitializing {
        __EasySwapOrderBook_init_unchained(
            newProtocolShare,
            newVault,
            EIP712Name,
            EIP712Version
        );
    }

    function __EasySwapOrderBook_init_unchained(uint128 newProtocolShare, address newVault, string memory EIP712Name, string memory EIP712Version) internal onlyInitializing {
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
        __Pausable_init();
        __OrderStorage_init(EIP712Name, EIP712Version);
        __ProtocolManager_init(newProtocolShare);
        setVault(newVault);
    }
    //event
    event LogWithdrawETH(address recipient, uint256 amount);
    event BatchMatchInnerError(uint256 offset, bytes msg);
    event LogSkipOrder(OrderKey orderKey, uint64 salt);
    event LogMakeOrder(OrderKey orderKey, LibOrder.Order order);

    //具体要接受nft以及eth的合约地址
    address private _vault;

    function setVault(address newVault) public onlyOwner {
        require(newVault != address(0), "HD: zero address");
        _vault = newVault;
    }

    //创建批量订单
    function makeOrders(LibOrder.Order[] calldata newOrders) external payable whenNotPaused nonReentrant returns (OrderKey[] memory orderKeys){
        uint256 orderAmount = newOrders.length;
        orderKeys = new OrderKey[](orderAmount);
        //定义ETHAmount，如果是买bid 行为，记录需要多少ETH,计算用户eth是否充足
        uint128 ETHAmount;
        for (uint256 i = 0; i < orderAmount;) {
            uint128 buyPrice = Price.unwrap(newOrders[i].price);
            OrderKey orderKey = makeOrdersTry(newOrders[i], buyPrice);
            orderKeys[i] = orderKey;
            //判断订单是否创建成功，如果订单创建成功，则累加ETHAmount
            if (orderKey != LibOrder.ORDERKEY_SENTINEL()) {
                ETHAmount += buyPrice;
            }
            unchecked{
                ++i;
            }
        }
        //判断用户余额是否够用
        if (msg.value > ETHAmount) {
            _msgSender().safeTransferETH(msg.value - ETHAmount);
        }

    }

    function cancelOrders(OrderKey[] calldata orderKeys) external whenNotPaused nonReentrant returns (bool[] memory successOrder){
        successOrder = new bool[](orderKeys.length);
        for (uint256 i = 0; i < orderKeys.length;) {
            successOrder[i] = cancelOrderTry(orderKeys[i]);
            unchecked{
                ++i;
            }
        }

    }

    function makeOrdersTry(LibOrder.Order orderInfo, uint128 buyPrice) internal returns (OrderKey orderKey){
        //校验条件
        if (
            orderInfo.maker != _msgSender() && Price.unwrap(orderInfo.price) != 0 &&
            orderInfo.salt != 0 && (orderInfo.expiry > block.timestamp || orderInfo.expiry == 0) &&
            orderStatus[LibOrder.hash(orderInfo)] == 0
        ) {
            orderKey = LibOrder.hash(orderInfo);
            if (orderInfo.side == LibOrder.Side.List) {
                //卖单操作
                //订单创建时，将nft转入资金池
                IEasySwapVault(_vault).depositNFT(orderKey, orderInfo.maker, orderInfo.nft.collection, orderInfo.nft.tokenId);
            } else if (orderInfo.side == LibOrder.Side.Bid) {
                //买单操作
                IEasySwapVault(_vault).depositETH(){value: uint256(buyPrice)}(orderKey, buyPrice);
            }
            //订单信息存储到OrderStorage合约
            addOrder(orderInfo);

            emit LogMakeOrder(orderKey, orderInfo);

        } else {
            //跳过订单
            emit LogSkipOrder(LibOrder.hash(orderInfo), orderInfo.salt);
        }

    }

    function cancelOrderTry(OrderKey orderKey) internal returns (bool success){
        LibOrder.Order order = orders[orderKey].order;
        //首先判断取消的订单请求发起者是否为订单创建者，只有订单创建者才可以取消订单
        if (order.maker == _msgSender() && orderStatus[orderKey] == 0) {
            if (order.side == LibOrder.Side.List) {
                IEasySwapVault(_vault).withdrawNFT(orderKey, order.maker, order.nft.collection, order.nft.tokenId);
            } else if (order.side == LibOrder.Side.Bid) {
                IEasySwapVault(_vault).withdrawETH(orderKey, Price.unwrap(order.price));
            }

            cancelOrder(order);
            orderStatus[orderKey] = CANCELLED;
        } else {
            emit LogSkipOrder(orderKey, order.salt);
        }
    }


}
