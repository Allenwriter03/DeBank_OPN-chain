// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract TimeLockVault is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    struct Lock {
        address owner;
        address token;
        uint256 amount;
        uint256 unlockTime;
        bool claimed;
    }

    uint256 public constant MAX_FEE_BPS = 500; 
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MIN_LOCK_DURATION = 1 days;
    uint256 public constant MAX_LOCK_DURATION = 5 * 365 days;

    uint256 public lockFeeBps;
    uint256 public claimFeeBps;
    uint256 public earlyWithdrawFeeBps;
    address public feeRecipient;

    mapping(address => bool) public supportedTokens; 
    mapping(uint256 => Lock) public locks;
    mapping(address => uint256[]) private _userLockIds;
    uint256 public nextLockId;

    event TokenSupportUpdated(address indexed token, bool supported);
    event FeesUpdated(uint256 lockFeeBps, uint256 claimFeeBps, uint256 earlyWithdrawFeeBps);
    event FeeRecipientUpdated(address indexed feeRecipient);
    event LockCreated(uint256 indexed lockId, address indexed owner, address token, uint256 amount, uint256 unlockTime);
    event LockToppedUp(uint256 indexed lockId, uint256 addedAmount, uint256 newTotal);
    event LockClaimed(uint256 indexed lockId, address indexed owner, uint256 payout, uint256 fee, bool early);

    constructor(
        address initialOwner,
        address initialFeeRecipient,
        uint256 initialLockFeeBps,
        uint256 initialClaimFeeBps,
        uint256 initialEarlyWithdrawFeeBps
    ) Ownable(initialOwner) {
        require(initialFeeRecipient != address(0), "fee recipient required");
        require(
            initialLockFeeBps <= MAX_FEE_BPS &&
            initialClaimFeeBps <= MAX_FEE_BPS &&
            initialEarlyWithdrawFeeBps <= MAX_FEE_BPS,
            "fee too high"
        );
        feeRecipient = initialFeeRecipient;
        lockFeeBps = initialLockFeeBps;
        claimFeeBps = initialClaimFeeBps;
        earlyWithdrawFeeBps = initialEarlyWithdrawFeeBps;
    }


    function createLock(address token, uint256 amount, uint256 duration)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 lockId)
    {
        require(duration >= MIN_LOCK_DURATION && duration <= MAX_LOCK_DURATION, "duration out of range");

        uint256 received = _pullFunds(token, amount);
        uint256 fee = (received * lockFeeBps) / BPS_DENOMINATOR;
        uint256 net = received - fee;
        require(net > 0, "amount too small after fee");

        lockId = nextLockId++;
        uint256 unlockTime = block.timestamp + duration;
        locks[lockId] = Lock({owner: msg.sender, token: token, amount: net, unlockTime: unlockTime, claimed: false});
        _userLockIds[msg.sender].push(lockId);

        if (fee > 0) _payOut(token, feeRecipient, fee);

        emit LockCreated(lockId, msg.sender, token, net, unlockTime);
    }

    function topUp(uint256 lockId, uint256 amount) external payable whenNotPaused nonReentrant {
        Lock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "not your lock");
        require(!lock.claimed, "already claimed");

        uint256 received = _pullFunds(lock.token, amount);
        uint256 fee = (received * lockFeeBps) / BPS_DENOMINATOR;
        uint256 net = received - fee;
        require(net > 0, "amount too small after fee");

        lock.amount += net;
        if (fee > 0) _payOut(lock.token, feeRecipient, fee);

        emit LockToppedUp(lockId, net, lock.amount);
    }

    function claim(uint256 lockId) external nonReentrant {
        Lock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "not your lock");
        require(!lock.claimed, "already claimed");

        bool early = block.timestamp < lock.unlockTime;
        uint256 feeBps = early ? earlyWithdrawFeeBps : claimFeeBps;
        uint256 amount = lock.amount;

        lock.claimed = true;

        uint256 fee = (amount * feeBps) / BPS_DENOMINATOR;
        uint256 payout = amount - fee;

        _payOut(lock.token, msg.sender, payout);
        if (fee > 0) _payOut(lock.token, feeRecipient, fee);

        emit LockClaimed(lockId, msg.sender, payout, fee, early);
    }

    function getUserLockIds(address user) external view returns (uint256[] memory) {
        return _userLockIds[user];
    }

    function getLock(uint256 lockId) external view returns (Lock memory) {
        return locks[lockId];
    }

    function _pullFunds(address token, uint256 amount) private returns (uint256 received) {
        if (token == address(0)) {
            require(amount == 0, "amount must be 0 for native OPN; use msg.value");
            require(msg.value > 0, "send OPN with this call");
            return msg.value;
        }

        require(msg.value == 0, "do not send OPN for a token lock");
        require(supportedTokens[token], "token not supported");
        require(amount > 0, "amount must be positive");

        IERC20 erc20 = IERC20(token);
        uint256 before = erc20.balanceOf(address(this));
        erc20.safeTransferFrom(msg.sender, address(this), amount);
        received = erc20.balanceOf(address(this)) - before;
    }

    function _payOut(address token, address to, uint256 amount) private {
        if (token == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "OPN transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }


    function setSupportedToken(address token, bool supported) external onlyOwner {
        require(token != address(0), "native OPN is always supported");
        supportedTokens[token] = supported;
        emit TokenSupportUpdated(token, supported);
    }

    function setFees(uint256 newLockFeeBps, uint256 newClaimFeeBps, uint256 newEarlyWithdrawFeeBps) external onlyOwner {
        require(
            newLockFeeBps <= MAX_FEE_BPS &&
            newClaimFeeBps <= MAX_FEE_BPS &&
            newEarlyWithdrawFeeBps <= MAX_FEE_BPS,
            "fee too high"
        );
        lockFeeBps = newLockFeeBps;
        claimFeeBps = newClaimFeeBps;
        earlyWithdrawFeeBps = newEarlyWithdrawFeeBps;
        emit FeesUpdated(newLockFeeBps, newClaimFeeBps, newEarlyWithdrawFeeBps);
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "zero address");
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {
        revert("use createLock or topUp");
    }

    fallback() external payable {
        revert("unknown call");
    }
}
