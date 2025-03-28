// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";


library  LibSafeTransferUpgradeable {
    function safeTransferETH(address to, uint256 amount) internal {
        bool success;
        assembly {
            success := call(gas(),to,amount,0,0,0,0)
        }
        require(success,"ETH Transfer failed");
    }


    function safeTransferNFT(IERC721 nft, address from, address to,uint256 tokenId) internal {
        bool success;
        assembly {
            //随机选一个内存槽地址，从0x40开始
            let freeMemoryPointer := mload(0x40)
            //函数选择器使用safeTransferFrom(address from, address to, uint256 tokenId)
            mstore(
                freeMemoryPointer,
                0x42842e0e00000000000000000000000000000000000000000000000000000000
            )
            //函数选择器占用4个字节，address 占用32个字节 token占用32个字节
            mstore(add(freeMemoryPointer,4),from)
            mstore(add(freeMemoryPointer,36),to)
            mstore(add(freeMemoryPointer,68),tokenId)
            //需要判断是否调用成功
            //两个条件，一.0位的第一个字节是1，表示true，返回的datasize要大于31，确保不是一个随机的非零数据
            //二，返回数据是空的，因为一些代币调用成功后不会返回任何内容，所以这个也成立
            success := and(
                or(
                    and(eq(mload(0),1),gt(returndatasize(),31)),
                    iszero(returndatasize())
                ),
            //0：不发送 ETH。
            //freeMemoryPointer：指向内存中存储的 calldata 的位置。
            //100：calldata 的长度（4 字节函数选择器 + 3 个 32 字节参数）。
            //0：返回数据的存储位置。
            //32：返回数据的最大长度。
                call(gas(),nft,0,freeMemoryPointer,100,0,32)
            )
        }
        require(success,"NFT Transfer Failed");
    }

    function safeTransferNFTs(IERC721 nft,address from, address to,uint256[] memory tokenIds) internal {
        bool success;
        uint256 length = tokenIds.length;
        for(uint256 i = 0;i<length; ){
            uint256 tokenId = tokenIds[i];
            assembly {
                let freeMemoryPointer := mload(0x40)
                mstore(
                    freeMemoryPointer,
                    0x42842e0e00000000000000000000000000000000000000000000000000000000
                )
                mstore(add(freeMemoryPointer,4),from)
                mstore(add(freeMemoryPointer,36),to)
                mstore(add(freeMemoryPointer,68),tokenId)
                success := and(
                    or(
                        and(eq(mload(0),1),gt(returndatasize(),31)),
                        iszero(returndatasize())
                    ),
                    call(gas(),nft,0,freeMemoryPointer,100,0,32)
                )
            }
            require(success,"NFT Transfer Failed");

            //使用unchecked关键字表示不进行溢出检查，节约gas
            unchecked{
                ++i;
            }
        }
    }

}
