// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ZKRandomStorage.sol";
import "./libraries/QueueTotal.sol";
import "./interfaces/IZKRandomCore.sol";
import "./interfaces/IZKRandomCallback.sol";
import "./interfaces/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract ZKRandomCore is IZKRandomCore, ZKRandomStorage, Ownable {
    using Counters for Counters.Counter;
    using QueueTotal for QueueTotal.Queue;

    struct Message {
        uint256 itemId;
        uint256 nonce;
        bytes32 hv;
        address callback;
        uint256 created;
        bool isDead;
    }

    struct Deposit {
        // Initial stake amount
        uint256 bond;
        uint256 balance;
        uint8 penaltyTimes;
        uint applyUnBoundTime;
        // 0: normal, 1: unbinding, 2: unbinded
        uint8 status;
    }

    uint8 constant NORMAL = 0;
    uint8 constant UNBINDING = 1;
    uint8 constant UNBINDED = 2;

    uint8 public constant Version = 1;
    bytes32 public constant PackedHeader = keccak256("function generateRandom(bytes32 key,uint256 deadline,uint8 v,bytes32 r,bytes32 s)");
    // pay config
    address public DepositToken;
    uint256 public MinDeposit = 10 * 10**10;
    uint256 public MessageTimeout = 5 minutes;
    uint256 public UnBindingTime = 2 minutes;

    uint8 MaxQueueValue = 5;

    mapping(uint256 => Counters.Counter) public ItemNonces;
    mapping(bytes32 => Message) public AcceptMessages;
    mapping(uint256 => QueueTotal.Queue) public Queues;
    mapping(uint256 => Deposit) public Deposits;
    // ItemId => (Nonce => requestKey)
    mapping(uint256 => mapping(uint256 => bytes32)) ItemNonceKey;

    event NewMessage(uint256 itemId, bytes32 requestKey, bytes32 hv, address callback, address origin);
    event NewRandom(uint256 itemId, bytes32 requestKey, bytes32 rv);
    event AddBound(uint256 projectId, uint256 payAmount, uint8 penaltyTimes, address user);
    event ApplyUnBond(uint256 projectId, uint256 balance);
    event UnBonded(uint256 projectId);
    // [startNonce, endNonce)
    event SkipAll(uint256 itemId, uint256 startNonce, uint256 endNonce);
    event SkipOne(uint256 itemId, uint256 nonce);

    modifier checkDeposit(uint256 itemId) {
        uint256 projectId = Items[itemId].projectId;
        require(Deposits[projectId].status == NORMAL, "ZKRandomCore/State error.");
        _checkDeposit(projectId);
        _;
    }

    function setToken(address addr) external onlyOwner {
        DepositToken = addr;
    }

    function getToken() external view returns(address, uint8) {
        return (DepositToken, IERC20(DepositToken).decimals());
    }

    function setMaxQueueValue(uint8 value) external onlyOwner {
        MaxQueueValue = value;
    }

    function setMinDeposit(uint256 value) external onlyOwner {
        MinDeposit = value;
    }

    function _checkDeposit(uint256 projectId) internal view {
        require(
            Deposits[projectId].penaltyTimes < 10,
            "ZKRandomCore/Max penaltyTimes."
        );
        require(
            Deposits[projectId].balance > 0,
            "ZKRandomCore/Project insufficient balance."
        );
    }

    function encodePacked(
        bytes32 header,
        bytes32 requestKey,
        Message memory message,
        uint256 deadline
    ) public view returns (bytes32 v) {
        // require(deadline >= block.timestamp, "OnlineRouter/Expire time.");

        bytes32 t = keccak256(
            abi.encode(
                header,
                requestKey,
                message.itemId,
                message.nonce,
                message.hv,
                message.callback,
                message.created,
                message.isDead,
                deadline,
                block.chainid
            )
        );
        v = keccak256( abi.encodePacked(
            "\x19Ethereum Signed Message:\n32" , t
        )) ;
    }

    function _revicedToken(
        address sender,
        address to,
        uint256 amount
    ) internal {
        IERC20(DepositToken).transferFrom(sender, to, amount);
    }

    function regist(
        string memory name,
        address oper,
        uint256 depositAmt
    ) external override returns (uint256 projectId) {
        require(depositAmt >= MinDeposit, "ZKRandomCore/Deposit is too less .");
        // need pay token.
        _revicedToken(msg.sender, address(this), depositAmt);
        projectId = _newProject(name, oper, depositAmt);
        Deposits[projectId] = Deposit({
            bond: depositAmt,
            balance: depositAmt,
            penaltyTimes: 0,
            applyUnBoundTime: 0,
            status: NORMAL
        });
    }

    function newItem(
        uint256 projectId,
        address caller,
        address pubkey,
        uint8 model
    ) external override returns (uint256 itemId) {
        itemId = _newItem(projectId, caller, pubkey, model);
    }

    function modifyItem(
        uint256 itemId, 
        address pubkey
    ) external override {
        _modifyItem(itemId, pubkey);
    }

    function addBond(uint256 projectId, uint8 timesValue) external override {
        Deposit storage deposit = Deposits[projectId];
        require(deposit.status == NORMAL, "ZKRandomCore/Not allow this operation.");

        if (timesValue > deposit.penaltyTimes) {
            timesValue = deposit.penaltyTimes;
        }
        uint256 payAmt = (deposit.bond / 10) * timesValue;
        _revicedToken(msg.sender, address(this), payAmt);
        deposit.balance += payAmt;
        deposit.penaltyTimes -= timesValue;
       
        emit AddBound(projectId, payAmt, deposit.penaltyTimes, msg.sender);
    }

    // You can withdraw at least 7 days after you apply for unbinding.
    // The unbinding state can call the `generateRandom` interface, but the `accept` interface cannot be called
    function applyUnBond(uint256 projectId) external override {
        Project memory project =  Projects[projectId];
        require(project.oper == msg.sender, "ZKRandomCore/Invaild commiter.");
        Deposit storage deposit = Deposits[projectId];
        require(deposit.status == NORMAL, "ZKRandomCore/Current state does not support unbinding.");
        require(deposit.balance > 0, "ZKRandomCore/Insufficient balance.");
        deposit.applyUnBoundTime = block.timestamp;
        deposit.status = UNBINDING;

        emit ApplyUnBond(projectId, deposit.balance);
    }

    function withdraw(uint256 projectId) external override {
        Project memory project =  Projects[projectId];
        require(project.oper == msg.sender, "ZKRandomCore/Invaild commiter.");
        Deposit storage deposit = Deposits[projectId];
        require(deposit.status == UNBINDING, "ZKRandomCore/Not allow this operation.");
        require((block.timestamp - deposit.applyUnBoundTime) >= UnBindingTime, "ZKRandomCore/Not up to the specified time.");

        IERC20(DepositToken).transfer(msg.sender, deposit.balance);

        deposit.balance = 0;
        deposit.status = UNBINDED;
        emit UnBonded(projectId);
    }

    function publishPrivateKey(uint256 itemId, bytes memory prikey) external override {
        _publishPrivateKey(itemId, prikey);
    }

    function _punish(uint256 itemId, bytes32 requestKey, uint256 projectId) internal {
        Deposit storage deposit = Deposits[projectId];

        require(deposit.penaltyTimes < 10, "ZKRandomCore/Max penalty times.");
        deposit.penaltyTimes += 1;
        uint256 rewardValue = deposit.bond / 10;
        //reward to reporter.
        IERC20(DepositToken).transfer(msg.sender, rewardValue);
        deposit.balance -= rewardValue;
        // notify

        emit Penalty(itemId, deposit.penaltyTimes, deposit.balance, requestKey, msg.sender, rewardValue);
    }

    function reportItemCheating(uint256 itemId) external {
        Item memory item = Items[itemId];
        require(item.model == STRICT, "ZKRandomCore/Only be called in strict model");
        uint256 headNonce = Queues[itemId].getFirst(
          ItemNonces[itemId].current()
        );
        bytes32 requestKey = ItemNonceKey[itemId][headNonce];
        require(requestKey != bytes32(0), "ZKRandomCore/To report invalid");
        Message storage message = AcceptMessages[requestKey];
        require(
            (message.created + MessageTimeout) < block.timestamp,
            "ZKRandomCore/Not cheating."
        );
        _doMessage(message, item.model);

        uint256 currentNonce = ItemNonces[itemId].current();
        for(uint256 i = headNonce + 1; i < currentNonce; i++) {
          bytes32 rk = ItemNonceKey[itemId][i];
          Message storage innerMessage = AcceptMessages[rk];
          _doMessage(innerMessage, item.model);
        }
        uint256 projectId = item.projectId;
        _punish(itemId, requestKey, projectId);
        emit SkipAll(itemId, headNonce, currentNonce);
    }

    function reportCheating(bytes32 requestKey) external {
        Message storage message = AcceptMessages[requestKey];
        require(
            message.isDead == false,
            "ZKRandomCore/This message is finished."
        );
        require(
            (message.created + MessageTimeout) < block.timestamp,
            "ZKRandomCore/Not cheating."
        );
        Item memory item = Items[message.itemId];
        require(item.model == NONSTRICT, "ZKRandomCore/Only be called in nostrict model");
        _doMessage(message, item.model);
        uint256 projectId = item.projectId;
        _punish(message.itemId, requestKey, projectId);
        emit SkipOne(message.itemId, message.nonce);
    }

    function _afterNewItem(uint256 itemId) internal override {
        // counter for item.
        ItemNonces[itemId] = Counters.Counter({_value: 0});
        Queues[itemId] = QueueTotal.init(MaxQueueValue);
    }

    function accept(
        address callback,
        uint256 itemId,
        bytes32 hv
    ) external override checkDeposit(itemId) returns (bytes32 requestKey) {
        // queue
        Item memory item = Items[itemId];
        require(item.pubkey != address(0), "ZKRandomCore/Item is not initialized.");
        //check item status
        require(item.isPublish == 0, "ZKRandomCore/Invaild item.");
        require(item.caller == msg.sender, "ZKRandomCore/Invaild request.");

        if (item.model == STRICT) {
            Queues[itemId].incr();
        }

        uint256 nonce = ItemNonces[itemId].current();
        ItemNonces[itemId].increment();
        requestKey = keccak256(
            abi.encode(item.projectId, item.caller, itemId, nonce)
        );

        AcceptMessages[requestKey] = Message({
            itemId: itemId,
            nonce: nonce,
            hv: hv,
            callback: callback,
            created: block.timestamp,
            isDead: false
        });
        ItemNonceKey[itemId][nonce] = requestKey;
        //emit
        emit NewMessage(itemId, requestKey, hv, callback, tx.origin);
    }

    function _checkPublicKey(
        bytes32 header,
        bytes32 key,
        Message memory message,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        address pubkey = ecrecover(
            encodePacked(header, key, message, deadline),
            v,
            r,
            s
        );
        require(
            pubkey == Items[message.itemId].pubkey,
            "ZKRandomCore/Sign key does not matched."
        );
    }

    function _notify(
        address callback,
        uint256 nonce,
        uint256 itemId,
        bytes32 key,
        bytes32 r
    ) internal returns (bytes32 rv) {
        rv = keccak256(
            abi.encode(
                callback,
                nonce,
                itemId,
                key,
                r,
                "Make by ZKRandom",
                block.timestamp
            )
        );
        IZKRandomCallback(callback).notify(itemId, key, rv);
    }

    function _doMessage(Message storage message, uint8 model) internal {
        if (model == STRICT) {
            Queues[message.itemId].decr();
        }
        message.isDead = true;
    }

    function generateRandom(
        bytes32 requestKey,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override returns (bytes32 rv) {
        // find message
        Message storage message = AcceptMessages[requestKey];
        Item memory item = Items[message.itemId];
        _checkDeposit(item.projectId);
        // donot delete RequestMessage.
        require(message.isDead == false, "ZKRandomCore/2.Invaild message.");
        if (item.model == STRICT) {
            require(
                Queues[message.itemId].isFirst(
                    message.nonce,
                    ItemNonces[message.itemId].current()
                ),
                "ZKRandomCore/1.Invaild message."
            );
        }
        require((message.created + MessageTimeout) > block.timestamp, "ZKRandomCore/3.Invaild message.");
        _checkPublicKey( PackedHeader, requestKey, message, deadline, v, r, s);
        rv = _notify(message.callback, message.nonce, message.itemId, requestKey, r);
        _doMessage(message, item.model);
        emit NewRandom(message.itemId, requestKey, rv);
    }

    function checkRequestKey(bytes32 requestKey) external view override returns(bool) {
      Message memory message = AcceptMessages[requestKey];
      return (message.created + MessageTimeout) > block.timestamp && !message.isDead;
    }
}
