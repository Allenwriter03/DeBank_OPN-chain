// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title TimeLockVault
/// @notice Lets any wallet lock native OPN or an owner-approved ERC-20 token (e.g. USDC)
///         for a duration of their choosing, optionally top up that same lock before it
///         matures, and claim it back afterwards. Early exit is allowed for a bigger
///         penalty fee instead of being completely blocked.
/// @dev Native OPN is represented internally by address(0). One shared contract holds
///      everyone's funds; per-user separation is enforced entirely through the Lock
///      struct's `owner` field and the `msg.sender` checks below, not through separate
///      contracts. There is intentionally no function anywhere that lets the owner move
///      a user's locked principal — owner-only functions only ever touch fee
///      configuration, never user balances.
contract TimeLockVault is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    struct Lock {
        address owner;
        address token;      // address(0) means native OPN
        uint256 amount;     // currently locked amount, net of fees already taken
        uint256 unlockTime; // block.timestamp at/after which a normal (non-penalised) claim is allowed
        bool claimed;
    }

    uint256 public constant MAX_FEE_BPS = 500; // hard ceiling: no fee can ever exceed 5%
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MIN_LOCK_DURATION = 1 days;
    uint256 public constant MAX_LOCK_DURATION = 5 * 365 days;

    uint256 public lockFeeBps;          // charged when a lock is created or topped up
    uint256 public claimFeeBps;         // charged on a normal claim, at or after maturity
    uint256 public earlyWithdrawFeeBps; // charged on a claim made before maturity
    address public feeRecipient;

    mapping(address => bool) public supportedTokens; // ERC-20 allowlist; native OPN is always allowed
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

    // ---------------------------------------------------------------------
    // User-facing actions
    // ---------------------------------------------------------------------

    /// @notice Lock native OPN or an approved ERC-20 token for `duration` seconds.
    /// @param token address(0) for native OPN, otherwise an owner-approved ERC-20 address.
    /// @param amount Amount to lock when `token` is an ERC-20. Must be 0 for native OPN;
    ///        send the native amount as msg.value instead.
    /// @param duration How long the funds stay locked, in seconds.
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

    /// @notice Add more funds to your own existing, unclaimed lock. Never changes the unlock date.
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

    /// @notice Claim a lock. Allowed at any time; claiming before the unlock date pays the
    ///         early-withdrawal fee instead of the normal claim fee, rather than being blocked
    ///         outright. Always works even while the contract is paused.
    function claim(uint256 lockId) external nonReentrant {
        Lock storage lock = locks[lockId];
        require(lock.owner == msg.sender, "not your lock");
        require(!lock.claimed, "already claimed");

        bool early = block.timestamp < lock.unlockTime;
        uint256 feeBps = early ? earlyWithdrawFeeBps : claimFeeBps;
        uint256 amount = lock.amount;

        lock.claimed = true; // state updated before any external transfer

        uint256 fee = (amount * feeBps) / BPS_DENOMINATOR;
        uint256 payout = amount - fee;

        _payOut(lock.token, msg.sender, payout);
        if (fee > 0) _payOut(lock.token, feeRecipient, fee);

        emit LockClaimed(lockId, msg.sender, payout, fee, early);
    }

    // ---------------------------------------------------------------------
    // Views, for the dashboard
    // ---------------------------------------------------------------------

    function getUserLockIds(address user) external view returns (uint256[] memory) {
        return _userLockIds[user];
    }

    function getLock(uint256 lockId) external view returns (Lock memory) {
        return locks[lockId];
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    /// @dev Pulls funds from the caller. For ERC-20s, measures the actual balance change
    ///      rather than trusting the `amount` parameter, so a fee-on-transfer or otherwise
    ///      non-standard token can never let someone record more than the contract truly
    ///      received.
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

    // ---------------------------------------------------------------------
    // Admin: fee configuration only. None of these touch a user's locked principal.
    // ---------------------------------------------------------------------

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

    /// @notice Pauses new locks and top-ups only. Claiming, including early withdrawal,
    ///         always stays open, even while paused.
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
