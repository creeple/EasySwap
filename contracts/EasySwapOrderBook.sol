// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


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
import {LibPayInfo} from "./library/LibPayInfo.sol";

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
    event LogCancel(OrderKey indexed orderKey, address indexed maker);
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
    function editOrders(LibOrder.EditDetail[] calldata editDetails) external payable whenNotPaused nonReentrant returns(OrderKey[] newOrderKeys){

        newOrderKeys = new OrderKey[](editDetails.length);
        uint256 bidETHAmount;
        for (uint256 i = 0; i < editDetails.length; ++i) {
            (OrderKey newOrderKey, uint256 bidPrice) = editOrderTry(
                editDetails[i].oldOrderKey,
                editDetails[i].newOrder
            );
            bidETHAmount += bidPrice;
            newOrderKeys[i] = newOrderKey;
        }

        if (msg.value > bidETHAmount) {
            _msgSender().safeTransferETH(msg.value - bidETHAmount);
        }

    }


    function matchOrders(LibOrder.MatchDetail[] calldata matchDetails) external payable whenNotPaused nonReentrant{
        uint128 buyETHAmount;
        for(uint256 i = 0;i<matchDetails.length;++i){
            LibOrder.MatchDetail matchDetail = matchDetails[i];
            uint128 buyPrice = matchOrderTry(matchDetail.sellOrder,matchDetail.buyOrder);
            buyETHAmount += buyPrice;
        }
        if(msg.value > buyETHAmount){
            _msgSender().safeTransferETH(msg.value-buyETHAmount);
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
            emit LogCancel(orderKey, order.maker);
            success = true;
        } else {
            emit LogSkipOrder(orderKey, order.salt);
        }
    }

    function editOrderTry(OrderKey oldOrderKey,LibOrder.Order newOrder) internal returns(OrderKey newOrderKey,uint256 bidPrice){

        LibOrder.Order memory oldOrder = orders[oldOrderKey].order;
        if (
            (oldOrder.saleKind != newOrder.saleKind) ||
            (oldOrder.side != newOrder.side) ||
            (oldOrder.maker != newOrder.maker) ||
            (oldOrder.nft.collection != newOrder.nft.collection) ||
            (oldOrder.nft.tokenId != newOrder.nft.tokenId)
        ) {
            emit LogSkipOrder(oldOrderKey, oldOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }
        //先校验订单是否合法
        if (
            newOrder.maker != _msgSender() ||
            newOrder.salt == 0 ||
            (newOrder.expiry < block.timestamp && newOrder.expiry != 0) ||
            orderStatus[LibOrder.hash(newOrder)] != 0 // order cannot be canceled or filled
        ) {
            emit LogSkipOrder(oldOrderKey, newOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }
        //取消旧订单
        cancelOrder(oldOrder);
        orderStatus[oldOrderKey] = CANCELLED;
        emit LogCancel(oldOrderKey, oldOrder.maker);

        newOrderKey = addOrder(newOrder);
        //make order
        if(oldOrder.side == LibOrder.Side.List){
            IEasySwapVault(_vault).editNFT(oldOrderKey, newOrderKey);
        }else if(oldOrder.side == LibOrder.Side.Bid){
            uint256 oldPrice = Price.unwrap(oldOrder.price);
            uint256 newPrice = Price.unwrap(newOrder.price);
            if (newPrice > oldPrice) {
                bidPrice = newPrice - oldPrice;
                IEasySwapVault(_vault).editETH{value: uint256(bidPrice)}(
                    oldOrderKey,
                    newOrderKey,
                    oldPrice,
                    newPrice,
                    oldOrder.maker
                );
            } else {
                IEasySwapVault(_vault).editETH(
                    oldOrderKey,
                    newOrderKey,
                    oldPrice,
                    newPrice,
                    oldOrder.maker
                );
            }
        }
        emit LogMakeOrder(newOrderKey,newOrder);

    }

    function matchOrderTry(LibOrder.Order sellOrder,LibOrder.Order buyOrder)internal returns(uint128 costValue){
        OrderKey sellOrderKey = LibOrder.hash(sellOrder);
        OrderKey buyOrderKey = LibOrder.hash(buyOrder);
        isMatchAvailable(sellOrder, buyOrder, sellOrderKey, buyOrderKey);
        if(_msgSender() == sellOrder.maker){
            //require(msgValue ==0);
            bool isSellExist = orders[sellOrderKey].order.maker != address(0);
            if(isSellExist){
                cancelOrder(sellOrder);
                orderStatus[sellOrderKey] = 1;
            }
            uint128 fillPrice = Price.unwrap(buyOrder.price);
            //算出手续费
            uint128 protocolFee = _shareToAmount(fillPrice,protocolShare);
            //先将ETH转移到本合约
            IEasySwapVault(_vault).withdrawETH(buyOrderKey,fillPrice,address(this));
            //在把手续费去掉后，转移给卖家
            sellOrder.maker.safeTransferETH(fillPrice-protocolFee);
            //将nft转移给买家
            IEasySwapVault(_vault).withdrawNFT(sellOrderKey,buyOrder.maker,sellOrder.nft.collection,sellOrder.nft.tokenId);

        }else if(_msgSender() == buyOrder.maker){
            uint128 buyPrice = Price.unwrap(buyOrder.price);
            uint128 fillPrice = Price.unwrap(sellOrder.price);
            IEasySwapVault(_vault).withdrawETH(buyOrderKey,buyPrice,address(this));
            cancelOrder(buyOrder);
            orderStatus[buyOrder] = 1;
            //算出手续费
            uint128 protocolFee = _shareToAmount(fillPrice,protocolShare);
            sellOrder.maker.safeTransferETH(fillPrice - protocolFee);
            if(buyPrice>fillPrice){
                buyOrder.maker.safeTransferETH(buyPrice-fillPrice);
            }
            IEasySwapVault(_vault).withdrawNFT(sellOrderKey,buyOrder.maker,sellOrder.nft.collection,sellOrder.nft.tokenId);
            costValue = buyPrice;
        }

    }
    function isMatchAvailable(LibOrder.Order memory sellOrder,LibOrder.Order memory buyOrder,OrderKey sellOrderKey,OrderKey buyOrderKey)internal view{
        require(OrderKey.unwrap(sellOrderKey) != OrderKey.unwrap(buyOrderKey),"same order");
        require(sellOrder.side == LibOrder.Side.List && buyOrder.side == LibOrder.Side.Bid,"side mismatch");
        require(sellOrder.saleKind == LibOrder.SaleKind.FixedPriceForItem,"kind mismatch");
        require(sellOrder.maker != buyOrder.maker, "HD: same maker");
        require(buyOrder.saleKind == LibOrder.SaleKind.FixedPriceForCollection || (sellOrder.nft.collection == buyOrder.nft.collection &&
            sellOrder.nft.tokenId == buyOrder.nft.tokenId),
            "HD: asset mismatch"
        );

    }
    function _shareToAmount(
        uint128 total,
        uint128 share
    ) internal pure returns (uint128) {
        return (total * share) / LibPayInfo.TOTAL_SHARE;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}

    uint256[50] private __gap;

}
