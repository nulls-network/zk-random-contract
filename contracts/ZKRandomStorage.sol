// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

abstract contract ZKRandomStorage {

    struct Project {
        string name;
        address oper;
    }

    struct Item {
        uint256 projectId;
        address pubkey;
        bytes prikey;
        address caller ;
        uint8 isPublish; // 0 - not published .
        // 0:Nonstrict mode , 1: Strict mode
        uint8 model;
    }

    uint8 constant NONSTRICT = 0;
    uint8 constant STRICT = 1;

    Project[] public Projects;
    Item[] public Items;
 
    mapping(address => bool) public UsedOfPublic;

    event NewProject(uint256 projectId, string name, address oper, uint256 depositAmt);
    event NewItem(uint256 projectId, uint256 itemId, address pubkey, uint8 model);
    event PublishPublicKey(uint256 itemId, bytes prikey);
    event ModifyItem(uint256 itemId, address pubkey);
    event Penalty(uint256 itemId , uint8 penaltyTimes, uint256 balance, bytes32 requestKey, address sender, uint256 rewardAmount);

    modifier onlyProjectOper(uint256 projectId) {
        require(
            Projects[projectId].oper == msg.sender,
            "ZKRandomStorage/Caller is not oper for project."
        );
        _;
    }

    function _newProject(string memory name, address oper, uint256 depositAmt)
        internal
        returns (uint256 projectId)
    {
        projectId = Projects.length;
        Projects.push(Project({name: name, oper: oper}));
        emit NewProject(projectId, name, oper, depositAmt);
    }

    function _newItem(uint256 projectId, address caller , address pubkey, uint8 model)
        internal
        onlyProjectOper(projectId)
        returns (uint256 itemId)
    {
        require(
            UsedOfPublic[pubkey] == false ,
            "ZKRandomStorage/Public key is used."
        );

        require(model == NONSTRICT || model == STRICT, "ZKRandomStorage/Invaild item model.");

        itemId = Items.length;
        Items.push(Item({
            projectId: projectId,
            pubkey: pubkey,
            prikey: new bytes(0),
            caller : caller ,
            isPublish: 0,
            model: model
        }));
        _afterNewItem( itemId ) ;
        if (pubkey != address(0)) {
            UsedOfPublic[pubkey] = true ;
        }

        emit NewItem(projectId, itemId, pubkey, model);
    }

    function _modifyItem(uint256 itemId, address pubKey) internal {
        Item storage item = Items[itemId];
        require(item.isPublish == 0 , "ZKRandomStorage/Invaild item.");
        require(item.caller == msg.sender, "ZKRandomStorage/Invaild commiter.");
        require(item.pubkey == address(0), "ZKRandomStorage/Repeated setting of pubkey.");
        require(
            UsedOfPublic[pubKey] == false ,
            "ZKRandomStorage/Public key is used."
        );

        item.pubkey = pubKey;
        UsedOfPublic[pubKey] = true ;
        emit ModifyItem(itemId, pubKey);
    }

    function _publishPrivateKey(uint256 itemId, bytes memory prikey) internal {
        Item storage item = Items[itemId];
        require(item.isPublish == 0 , "ZKRandomStorage/Invaild item.");
        require(item.caller == msg.sender, "ZKRandomStorage/Invaild commiter.");
        item.prikey = prikey;
        item.isPublish = 1 ;
        emit PublishPublicKey(itemId, prikey);
    }

    function _afterNewItem( uint256 itemId ) internal virtual {}

}