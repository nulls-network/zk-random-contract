// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/**
 *  Notify to game
 */
interface IZKRandomCallback {

    event ZKRandomMessage( uint item , address player , bytes32 hv , bytes32 key ) ;

    // Receive proxy's message 
    function notify( uint item , bytes32 key , bytes32 rv ) external returns ( bool ) ;

}