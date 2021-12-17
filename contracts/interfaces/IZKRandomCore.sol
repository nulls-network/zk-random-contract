// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IZKRandomCore {
    function regist(
        string memory name,
        address oper,
        uint256 depositAmt
    ) external returns (uint256 projectId);

    function accept(
        address callback,
        uint256 itemId,
        bytes32 hv
    ) external returns (bytes32 requestKey);

    function generateRandom(
        bytes32 key,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32 rv);

    function newItem(
        uint256 projectId,
        address caller,
        address pubkey,
        uint8 model
    ) external returns (uint256 itemId);

    function modifyItem(
        uint256 itemId, 
        address pubkey
    ) external;

    function addBond(
        uint256 projectId, 
        uint8 timesValue
    ) external;

    function applyUnBond(
        uint256 projectId
    ) external;

    function withdraw(
        uint256 projectId
    ) external;

    function publishPrivateKey(
        uint256 itemId, 
        bytes memory prikey
    ) external;

    function checkRequestKey(
      bytes32 requestKey
    ) external view returns(bool);
}
