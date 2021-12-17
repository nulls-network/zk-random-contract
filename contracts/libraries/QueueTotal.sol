// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

library QueueTotal {

    struct Queue {
        uint8 total ;
        uint8 max ;
    }

    function init(uint8 max ) internal pure returns( Queue memory queue ) {
        require( max < 0xff , "QueueTotal/less than 0xff.");
        queue = Queue({
            total : 0 ,
            max : max 
        }) ;
    }

    function incr(Queue storage queue ) internal {
        require( queue.total <= queue.max , "QueueTotal/The maximum value has been reached." );
        queue.total += 1 ;
    }

    function decr(Queue storage queue ) internal {
        require( queue.total > 0 , "QueueTotal/Queue is empty.");
        queue.total -= 1 ;
    }

    function getFirst(Queue memory queue, uint256 maxNonce) internal pure returns ( uint256 firstNonce) {
        return (maxNonce - queue.total);
    }

    function isFirst(Queue memory queue , uint256 currentNonce , uint256 maxNonce ) internal pure returns ( bool isOk ) {
        isOk = currentNonce == getFirst(queue, maxNonce);
    }

}