//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NullsERC20Token is ERC20 {

    address Owner ;
    address Oper ;
    uint8 Decimals = 6;

    modifier onlyOwner() {
        require( msg.sender == Owner , "NullsERC20Token/No role." );
        _ ; 
    }

    modifier onlyOper() {
        require( msg.sender == Oper , "NullsERC20Token/No oper role." );
        _ ;
    }

    function decimals() public view override returns (uint8) {
        return Decimals;
    }

    constructor() ERC20("NullsERC20 Token ","T-NET") {
        Owner = msg.sender ;
        Oper = msg.sender ;
    }

    function modifierOwner( address owner ) external onlyOwner {
        Owner = owner ;
    }

    function modifierOper( address oper ) external onlyOwner {
        Oper = oper ;
    }

    function mint( address player , uint total ) external onlyOper {
        _mint( player , total );
    }

    function burn( address player , uint total ) external onlyOper {
        _burn( player , total );
    }

}
