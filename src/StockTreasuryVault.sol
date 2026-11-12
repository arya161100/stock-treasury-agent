// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "./interfaces/IERC20.sol";
import {IStockRouter} from "./interfaces/IStockRouter.sol";
import {SafeERC20} from "./lib/SafeERC20.sol";

/// @title StockTreasuryVault
/// @notice Policy vault for an agent that earns USDC and may invest only a user-set
///         share of surplus into allowlisted stock tokens.
///
/// Allocation rules (enforced on every `deposit` / `syncRevenue`):
///   1. Operating costs and the operating-reserve target come first.
///      Incoming USDC fills `operatingReserveTarget` before anything is investable.
///   2. Of the remaining surplus, `allocationBps / 10_000` is credited to
///      `investable`. The rest is retained cash. The agent cannot invest retained
///      cash or the reserve.
///   3. `allocate` spends only `investable`, only to an allowlisted stock via the
///      allowlisted router, and only inside per-tx and daily caps.
///   4. Both `allocate` and `payOperatingCost` revert `ReserveBreach` if the USDC
///      balance would fall below `operatingReserveTarget`. The agent has no
///      withdraw function. Only the human owner can move the reserve.
///
/// @dev TESTNET / COMPETITION PROTOTYPE. Mock stock tokens used with this vault
///      are NOT real securities and confer no rights in any public company.
contract StockTreasuryVault {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotOwner();
    error NotAgent();
    error ZeroAddress();
    error ZeroAmount();
    error Paused();
    error NotPaused();
    error InvalidBps();
    error InvalidCap();
    error PolicyNotSet();
    error StockNotAllowed(address stock);
    error RouterNotSet();
    error CostRecipientNotAllowed(address to);
    error ReserveBreach(uint256 balance, uint256 amount, uint256 reserveTarget);
    error ExceedsInvestable(uint256 requested, uint256 investable_);
    error PerTxCapExceeded(uint256 requested, uint256 cap);
    error DailyCapExceeded(uint256 requested, uint256 used, uint256 cap);
    error Reentrancy();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AgentSet(address indexed previousAgent, address indexed newAgent);
    event PolicySet(
        uint16 allocationBps, uint256 operatingReserveTarget, uint256 perTxCap, uint256 dailyCap
    );
    event StockAllowlisted(address indexed stock, bool allowed);
    event CostRecipientAllowlisted(address indexed recipient, bool allowed);
    event RouterSet(address indexed router);
    event KillSwitch(bool paused);
    event Deposited(address indexed from, uint256 amount);
    event RevenueSynced(uint256 incoming, uint256 toReserve, uint256 toInvestable, uint256 toRetained);
    event Allocated(address indexed agent, address indexed stock, uint256 usdcIn, uint256 stockOut, uint256 investableRemaining);
    event OperatingCostPaid(address indexed to, uint256 amount, bytes32 reason, uint256 investableRemaining);
    event OwnerWithdraw(address indexed token, address indexed to, uint256 amount);

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    uint256 public constant BPS_DENOM = 10_000;
    uint256 public constant DAY = 1 days;

    IERC20 public immutable usdc;

    address public owner;
    address public agent;
    address public router;
    bool public paused;
    bool public policySet;

    uint16 public allocationBps;
    uint256 public operatingReserveTarget;
    uint256 public perTxCap;
    uint256 public dailyCap;

    /// @notice USDC the agent is allowed to swap into allowlisted stocks.
    uint256 public investable;
    /// @notice Last USDC balance that has been run through the allocation split.
    uint256 public lastAccounted;

    uint256 public dailyUsed;
    uint64 public dailyWindow;

    mapping(address => bool) public allowedStocks;
    mapping(address => bool) public allowedCostRecipients;
    mapping(address => uint256) private _stockIndex; // 1-based
    address[] private _stockList;

    uint256 private _locked;

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier nonReentrant() {
        if (_locked == 1) revert Reentrancy();
        _locked = 1;
        _;
        _locked = 0;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address usdc_, address owner_, address agent_, address router_) {
        if (usdc_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        usdc = IERC20(usdc_);
        owner = owner_;
        agent = agent_;
        router = router_;
        emit OwnershipTransferred(address(0), owner_);
        emit AgentSet(address(0), agent_);
        if (router_ != address(0)) emit RouterSet(router_);
    }

    // -------------------------------------------------------------------------
    // Owner: policy, roles, kill-switch
    // -------------------------------------------------------------------------

    /// @notice Set the allocation split, reserve floor, and caps. Required before allocate.
    /// @param allocationBps_ Share of surplus (after filling the reserve) that becomes investable. 7000 = 70%.
    /// @param operatingReserveTarget_ USDC units (6 decimals) the agent can never spend or invest through.
    /// @param perTxCap_ Max USDC per `allocate` call.
    /// @param dailyCap_ Max USDC allocated per UTC day.
    function setPolicy(
        uint16 allocationBps_,
        uint256 operatingReserveTarget_,
        uint256 perTxCap_,
        uint256 dailyCap_
    ) external onlyOwner {
        if (allocationBps_ > BPS_DENOM) revert InvalidBps();
        if (perTxCap_ == 0 || dailyCap_ == 0) revert InvalidCap();
        allocationBps = allocationBps_;
        operatingReserveTarget = operatingReserveTarget_;
        perTxCap = perTxCap_;
        dailyCap = dailyCap_;
        policySet = true;
        // If the target rose, shrink investable so the reserve floor wins.
        _clampInvestable(usdc.balanceOf(address(this)));
        emit PolicySet(allocationBps_, operatingReserveTarget_, perTxCap_, dailyCap_);
    }

    function setAgent(address agent_) external onlyOwner {
        if (agent_ == address(0)) revert ZeroAddress();
        emit AgentSet(agent, agent_);
        agent = agent_;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setRouter(address router_) external onlyOwner {
        if (router_ == address(0)) revert ZeroAddress();
        router = router_;
        emit RouterSet(router_);
    }

    function setStockAllowed(address stock, bool allowed) external onlyOwner {
        if (stock == address(0)) revert ZeroAddress();
        allowedStocks[stock] = allowed;
        if (allowed && _stockIndex[stock] == 0) {
            _stockList.push(stock);
            _stockIndex[stock] = _stockList.length;
        }
        emit StockAllowlisted(stock, allowed);
    }

    function setCostRecipient(address recipient, bool allowed) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        allowedCostRecipients[recipient] = allowed;
        emit CostRecipientAllowlisted(recipient, allowed);
    }

    /// @notice Owner kill-switch. While paused the agent cannot allocate or pay costs.
    function pause() external onlyOwner {
        if (paused) revert Paused();
        paused = true;
        emit KillSwitch(true);
    }

    function unpause() external onlyOwner {
        if (!paused) revert NotPaused();
        paused = false;
        emit KillSwitch(false);
    }

    /// @notice The only path that can move the operating reserve or stock holdings out.
    ///         The agent cannot call this.
    function ownerWithdraw(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, amount);
        if (token == address(usdc)) {
            lastAccounted = usdc.balanceOf(address(this));
            _clampInvestable(lastAccounted);
        }
        emit OwnerWithdraw(token, to, amount);
    }

    // -------------------------------------------------------------------------
    // Revenue
    // -------------------------------------------------------------------------

    /// @notice Pull USDC from the caller and split it under the current policy.
    function deposit(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!policySet) revert PolicyNotSet();
        _syncRevenue();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        _accountIncoming(amount);
        emit Deposited(msg.sender, amount);
    }

    /// @notice Account USDC that arrived by direct transfer (x402 settlement pays the vault).
    function syncRevenue() external {
        _syncRevenue();
    }

    function _syncRevenue() internal {
        uint256 bal = usdc.balanceOf(address(this));
        if (bal > lastAccounted) {
            _accountIncoming(bal - lastAccounted);
        } else if (bal < lastAccounted) {
            lastAccounted = bal;
            _clampInvestable(bal);
        }
    }

    /// @dev Split `incoming` USDC: fill the reserve gap first, then allocationBps of the rest
    ///      becomes investable and the remainder is retained (not credited to investable).
    function _accountIncoming(uint256 incoming) internal {
        uint256 reserveFilled = _effectiveReserve(lastAccounted);
        uint256 reserveGap =
            operatingReserveTarget > reserveFilled ? operatingReserveTarget - reserveFilled : 0;
        uint256 toReserve = incoming < reserveGap ? incoming : reserveGap;
        uint256 surplus = incoming - toReserve;
        uint256 toInvestable = (surplus * uint256(allocationBps)) / BPS_DENOM;
        uint256 toRetained = surplus - toInvestable;
        investable += toInvestable;
        lastAccounted += incoming;
        emit RevenueSynced(incoming, toReserve, toInvestable, toRetained);
    }

    function _effectiveReserve(uint256 bal) internal view returns (uint256) {
        return bal < operatingReserveTarget ? bal : operatingReserveTarget;
    }

    /// @dev If the reserve target has risen (or USDC left via ownerWithdraw), investable
    ///      shrinks so that reserve + investable never exceeds the live balance.
    function _clampInvestable(uint256 bal) internal {
        uint256 reserved = _effectiveReserve(bal);
        if (investable + reserved > bal) {
            investable = bal - reserved;
        }
    }

    // -------------------------------------------------------------------------
    // Agent: allocate and pay operating costs
    // -------------------------------------------------------------------------

    /// @notice Swap investable USDC for an allowlisted stock. Reverts rather than
    ///         touching the operating reserve.
    function allocate(address stock, uint256 usdcAmount, uint256 minOut)
        external
        onlyAgent
        whenNotPaused
        nonReentrant
        returns (uint256 stockOut)
    {
        if (usdcAmount == 0) revert ZeroAmount();
        if (!policySet) revert PolicyNotSet();
        _syncRevenue();
        if (!allowedStocks[stock]) revert StockNotAllowed(stock);
        if (router == address(0)) revert RouterNotSet();
        if (usdcAmount > investable) revert ExceedsInvestable(usdcAmount, investable);
        if (usdcAmount > perTxCap) revert PerTxCapExceeded(usdcAmount, perTxCap);
        _tapDaily(usdcAmount);

        uint256 bal = usdc.balanceOf(address(this));
        if (bal < usdcAmount || bal - usdcAmount < operatingReserveTarget) {
            revert ReserveBreach(bal, usdcAmount, operatingReserveTarget);
        }

        investable -= usdcAmount;

        usdc.forceApprove(router, usdcAmount);
        stockOut = IStockRouter(router).swapExactUSDCForStock(stock, usdcAmount, minOut, address(this));
        usdc.forceApprove(router, 0);

        lastAccounted = usdc.balanceOf(address(this));
        emit Allocated(msg.sender, stock, usdcAmount, stockOut, investable);
    }

    /// @notice Pay an allowlisted operating-cost recipient from retained cash first,
    ///         then from investable. Never from the reserve.
    function payOperatingCost(address to, uint256 amount, bytes32 reason)
        external
        onlyAgent
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (!allowedCostRecipients[to]) revert CostRecipientNotAllowed(to);
        _syncRevenue();

        uint256 bal = usdc.balanceOf(address(this));
        if (bal < amount || bal - amount < operatingReserveTarget) {
            revert ReserveBreach(bal, amount, operatingReserveTarget);
        }

        _clampInvestable(bal);
        uint256 reserved = _effectiveReserve(bal);
        uint256 retained_ = bal - reserved - investable;
        if (amount > retained_) {
            investable -= (amount - retained_);
        }

        usdc.safeTransfer(to, amount);
        lastAccounted = usdc.balanceOf(address(this));
        emit OperatingCostPaid(to, amount, reason, investable);
    }

    function _tapDaily(uint256 amount) internal {
        uint64 window = uint64((block.timestamp / DAY) * DAY);
        if (window != dailyWindow) {
            dailyWindow = window;
            dailyUsed = 0;
        }
        if (dailyUsed + amount > dailyCap) {
            revert DailyCapExceeded(amount, dailyUsed, dailyCap);
        }
        dailyUsed += amount;
    }

    // -------------------------------------------------------------------------
    // Views (dashboard / judges)
    // -------------------------------------------------------------------------

    struct Preview {
        address usdc;
        address owner;
        address agent;
        address router;
        uint16 allocationBps;
        uint256 operatingReserveTarget;
        uint256 perTxCap;
        uint256 dailyCap;
        uint256 dailyUsed;
        uint64 dailyWindow;
        bool paused;
        bool policySet;
        uint256 usdcBalance;
        uint256 investable;
        uint256 reservedEffective;
        uint256 retained;
        uint256 lastAccounted;
    }

    function preview() external view returns (Preview memory p) {
        uint256 bal = usdc.balanceOf(address(this));
        uint256 reserved = _effectiveReserve(bal);
        uint256 inv = investable;
        if (inv + reserved > bal) inv = bal - reserved;
        p.usdc = address(usdc);
        p.owner = owner;
        p.agent = agent;
        p.router = router;
        p.allocationBps = allocationBps;
        p.operatingReserveTarget = operatingReserveTarget;
        p.perTxCap = perTxCap;
        p.dailyCap = dailyCap;
        p.dailyUsed = dailyUsedFor(block.timestamp);
        p.dailyWindow = dailyWindow;
        p.paused = paused;
        p.policySet = policySet;
        p.usdcBalance = bal;
        p.investable = inv;
        p.reservedEffective = reserved;
        p.retained = bal - reserved - inv;
        p.lastAccounted = lastAccounted;
    }

    function dailyUsedFor(uint256 timestamp) public view returns (uint256) {
        uint64 window = uint64((timestamp / DAY) * DAY);
        return window == dailyWindow ? dailyUsed : 0;
    }

    function retained() public view returns (uint256) {
        uint256 bal = usdc.balanceOf(address(this));
        uint256 reserved = _effectiveReserve(bal);
        uint256 inv = investable;
        if (inv + reserved > bal) return 0;
        return bal - reserved - inv;
    }

    function stockCount() external view returns (uint256) {
        return _stockList.length;
    }

    function stockAt(uint256 i) external view returns (address) {
        return _stockList[i];
    }

    function holdings() external view returns (address[] memory tokens, uint256[] memory balances) {
        uint256 n = _stockList.length;
        tokens = new address[](n);
        balances = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            tokens[i] = _stockList[i];
            balances[i] = IERC20(_stockList[i]).balanceOf(address(this));
        }
    }

    /// @notice Off-chain helper: the largest USDC the agent could allocate right now
    ///         (min of investable, per-tx cap, remaining daily cap, and headroom above reserve).
    function maxAllocatable() public view returns (uint256) {
        if (paused || !policySet || router == address(0)) return 0;
        uint256 bal = usdc.balanceOf(address(this));
        if (bal <= operatingReserveTarget) return 0;
        uint256 headroom = bal - operatingReserveTarget;
        uint256 inv = investable;
        if (inv + _effectiveReserve(bal) > bal) inv = headroom;
        uint256 cap = perTxCap < inv ? perTxCap : inv;
        uint256 used = dailyUsedFor(block.timestamp);
        uint256 dailyLeft = dailyCap > used ? dailyCap - used : 0;
        if (dailyLeft < cap) cap = dailyLeft;
        if (headroom < cap) cap = headroom;
        return cap;
    }
}
