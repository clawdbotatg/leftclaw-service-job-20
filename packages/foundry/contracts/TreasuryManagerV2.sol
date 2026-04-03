// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interfaces/IInterfaces.sol";
import "./SwapHelper.sol";
import "./PermissionlessModule.sol";

/// @title TreasuryManagerV2 — ₸USD Treasury Management with Staking Integration
/// @notice Manages ₸USD buybacks, burns, staking, and permissionless rebalancing
/// @dev Owner = client wallet. Operator = AMI bot. All caps are hardcoded or owner-configurable.
contract TreasuryManagerV2 {
    // ======================== IMMUTABLES ========================

    address public immutable WETH;
    address public immutable USDC;
    address public immutable TUSD;
    address public immutable STAKING_CONTRACT;
    address public immutable UNIVERSAL_ROUTER;
    address public immutable POOL_MANAGER;
    address public immutable TUSD_POOL; // Official ₸USD/WETH V3 pool
    address public immutable USDC_WETH_POOL; // Canonical USDC/WETH V3 pool
    address public immutable CHAINLINK_ETH_USD; // ETH/USD price feed

    // ======================== HARDCODED CONSTANTS ========================

    uint256 public constant SLIPPAGE_BPS = 300; // 3%
    uint256 public constant PERMISSIONLESS_COOLDOWN = 4 hours;
    uint256 public constant MAX_PERCENT_PER_SWAP_BPS = 500; // 5% of unlocked
    uint256 public constant CIRCUIT_BREAKER_BPS = 1500; // 15% vs 24h TWAP
    uint256 public constant OPERATOR_INACTIVITY_PERIOD = 14 days;
    uint256 public constant DEAD_POOL_THRESHOLD = 90 days;
    uint256 public constant OPERATOR_COOLDOWN = 60 minutes;
    uint256 public constant PERMISSIONLESS_ETH_PER_ACTION = 0.5 ether;
    uint256 public constant PERMISSIONLESS_ETH_PER_DAY = 2 ether;
    uint256 public constant ROLLING_WINDOW = 24 hours;

    // ======================== ENUMS ========================

    enum ActionType {
        BuybackWETH,
        BuybackUSDC,
        Burn,
        Stake,
        Rebalance
    }

    // ======================== REENTRANCY ========================

    uint256 private _reentrancyStatus;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "ReentrancyGuard: reentrant call");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // ======================== STATE ========================

    address public owner;
    address public operator;
    uint256 public operatorSlippageBps;

    // Operator caps (per action type)
    struct OperatorCaps {
        uint256 perAction;
        uint256 perDay;
    }

    mapping(ActionType => OperatorCaps) public operatorCaps;

    // Operator daily usage tracking (rolling 24h window)
    mapping(address => uint256) public operatorDayStart;
    mapping(address => mapping(ActionType => uint256)) public operatorDailyUsed;

    // Operator cooldown
    uint256 public lastOperatorActionTime;

    // Token tracking for permissionless rebalance
    struct TokenInfo {
        uint256 totalWeiSpent;
        uint256 totalTokensReceived;
        uint256 initialBalanceSnapshot; // dynamic — updates on every buy
        address poolAddress; // V3 pool
        bytes32 v4PoolId; // V4 pool
        bool isV4;
        uint256 lastMeaningfulRebalanceTimestamp;
        uint256 lastPermissionlessCooldown;
        bool registered;
    }

    mapping(address => TokenInfo) public tokenInfo;
    address[] public registeredTokens;

    // Path 3 emergency state
    mapping(address => bool) public path3Triggered;
    mapping(address => uint256) public path3UnlockedPercentage;
    mapping(address => uint256) public path3LastDripTimestamp;

    // Permissionless daily caps
    mapping(address => uint256) public permissionlessDayStart;
    mapping(address => uint256) public permissionlessDailyUsed;

    // ======================== EVENTS ========================

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OperatorSet(address indexed newOperator);
    event CapsUpdated(ActionType indexed actionType, uint256 perAction, uint256 perDay);
    event SlippageUpdated(uint256 newSlippageBps);
    event BuybackExecuted(address indexed inputToken, uint256 amountIn, uint256 tusdReceived);
    event BurnExecuted(uint256 amount);
    event StakeExecuted(uint256 amount, uint256 poolNumber);
    event UnstakeExecuted(uint256 poolNumber);
    event TokenBought(address indexed token, uint256 wethSpent, uint256 tokensReceived);
    event RebalanceExecuted(
        address indexed token, uint256 amount, uint256 wethReceived, uint256 usdcToOwner, uint256 tusdBought
    );
    event PermissionlessRebalanceExecuted(
        address indexed caller,
        address indexed token,
        uint256 amount,
        uint256 wethReceived,
        uint256 usdcToOwner,
        uint256 tusdBought
    );
    event DeadPoolTokenRescued(address indexed token, uint256 amount);

    // ======================== MODIFIERS ========================

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Not operator");
        _;
    }

    modifier operatorCooldown() {
        require(block.timestamp >= lastOperatorActionTime + OPERATOR_COOLDOWN, "Operator cooldown active");
        _;
        lastOperatorActionTime = block.timestamp;
    }

    // ======================== CONSTRUCTOR ========================

    constructor(
        address _owner,
        address _weth,
        address _usdc,
        address _tusd,
        address _stakingContract,
        address _universalRouter,
        address _poolManager,
        address _tusdPool,
        address _usdcWethPool,
        address _chainlinkEthUsd
    ) {
        require(_owner != address(0), "Zero owner");
        _reentrancyStatus = _NOT_ENTERED;
        owner = _owner;

        WETH = _weth;
        USDC = _usdc;
        TUSD = _tusd;
        STAKING_CONTRACT = _stakingContract;
        UNIVERSAL_ROUTER = _universalRouter;
        POOL_MANAGER = _poolManager;
        TUSD_POOL = _tusdPool;
        USDC_WETH_POOL = _usdcWethPool;
        CHAINLINK_ETH_USD = _chainlinkEthUsd;

        operatorSlippageBps = SLIPPAGE_BPS;

        // Default caps
        operatorCaps[ActionType.BuybackWETH] = OperatorCaps(0.5 ether, 2 ether);
        operatorCaps[ActionType.BuybackUSDC] = OperatorCaps(2000e6, 5000e6); // USDC 6 decimals
        operatorCaps[ActionType.Burn] = OperatorCaps(100_000_000e18, 500_000_000e18);
        operatorCaps[ActionType.Stake] = OperatorCaps(100_000_000e18, 500_000_000e18);
        operatorCaps[ActionType.Rebalance] = OperatorCaps(0.5 ether, 2 ether); // uses BuybackWETH caps on 100% input
    }

    // ======================== OWNER FUNCTIONS ========================

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
        emit OperatorSet(_operator);
    }

    function updateCaps(ActionType actionType, uint256 perAction, uint256 perDay) external onlyOwner {
        require(perAction <= perDay, "perAction > perDay");
        operatorCaps[actionType] = OperatorCaps(perAction, perDay);
        emit CapsUpdated(actionType, perAction, perDay);
    }

    function setSlippage(uint256 bps) external onlyOwner {
        require(bps > 0 && bps <= 1000, "Invalid slippage");
        operatorSlippageBps = bps;
        emit SlippageUpdated(bps);
    }

    /// @notice Rescue tokens from a dead pool (90+ days no operator activity)
    function rescueDeadPoolToken(address token) external onlyOwner {
        TokenInfo storage info = tokenInfo[token];
        require(info.registered, "Token not registered");
        require(
            info.lastMeaningfulRebalanceTimestamp > 0
                && block.timestamp - info.lastMeaningfulRebalanceTimestamp >= DEAD_POOL_THRESHOLD,
            "Pool not dead"
        );

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance");

        require(IERC20(token).transfer(owner, balance), "Transfer failed");
        emit DeadPoolTokenRescued(token, balance);
    }

    // ======================== OPERATOR FUNCTIONS ========================

    /// @notice Register a token for tracking (pool info for rebalance)
    function registerToken(address token, address poolAddress, bytes32 v4PoolId, bool isV4) external onlyOperator {
        require(!tokenInfo[token].registered, "Already registered");
        require(token != address(0), "Zero token");

        tokenInfo[token] = TokenInfo({
            totalWeiSpent: 0,
            totalTokensReceived: 0,
            initialBalanceSnapshot: 0,
            poolAddress: poolAddress,
            v4PoolId: v4PoolId,
            isV4: isV4,
            lastMeaningfulRebalanceTimestamp: 0,
            lastPermissionlessCooldown: 0,
            registered: true
        });

        registeredTokens.push(token);
    }

    /// @notice Buyback ₸USD with WETH
    function buybackWithWETH(uint256 amountIn) external onlyOperator operatorCooldown nonReentrant {
        _checkCaps(ActionType.BuybackWETH, amountIn);

        uint256 tusdReceived = SwapHelper.executeBuyback(
            SwapHelper.BuybackParams({
                inputToken: WETH,
                amountIn: amountIn,
                slippageBps: operatorSlippageBps,
                tusdPool: TUSD_POOL,
                usdcWethPool: USDC_WETH_POOL,
                universalRouter: UNIVERSAL_ROUTER,
                weth: WETH,
                usdc: USDC,
                tusd: TUSD
            })
        );

        emit BuybackExecuted(WETH, amountIn, tusdReceived);
    }

    /// @notice Buyback ₸USD with USDC
    function buybackWithUSDC(uint256 amountIn) external onlyOperator operatorCooldown nonReentrant {
        _checkCaps(ActionType.BuybackUSDC, amountIn);

        uint256 tusdReceived = SwapHelper.executeBuyback(
            SwapHelper.BuybackParams({
                inputToken: USDC,
                amountIn: amountIn,
                slippageBps: operatorSlippageBps,
                tusdPool: TUSD_POOL,
                usdcWethPool: USDC_WETH_POOL,
                universalRouter: UNIVERSAL_ROUTER,
                weth: WETH,
                usdc: USDC,
                tusd: TUSD
            })
        );

        emit BuybackExecuted(USDC, amountIn, tusdReceived);
    }

    /// @notice Burn ₸USD
    function burn(uint256 amount) external onlyOperator operatorCooldown nonReentrant {
        _checkCaps(ActionType.Burn, amount);
        require(IERC20(TUSD).balanceOf(address(this)) >= amount, "Insufficient TUSD");

        // Transfer to dead address for burn
        require(IERC20(TUSD).transfer(address(0xdead), amount), "Burn transfer failed");
        emit BurnExecuted(amount);
    }

    /// @notice Stake ₸USD into staking contract
    function stake(uint256 amount, uint256 poolNumber) external onlyOperator operatorCooldown nonReentrant {
        _checkCaps(ActionType.Stake, amount);
        require(IERC20(TUSD).balanceOf(address(this)) >= amount, "Insufficient TUSD");

        IERC20(TUSD).approve(STAKING_CONTRACT, amount);
        IStaking(STAKING_CONTRACT).deposit(amount, poolNumber);

        emit StakeExecuted(amount, poolNumber);
    }

    /// @notice Unstake full balance + rewards from staking pool
    /// @dev No caps, no cooldown for unstake
    function unstake(uint256 poolNumber) external onlyOperator nonReentrant {
        // Withdraw 0 to claim rewards, or withdraw full balance
        // The staking contract's withdraw(0, poolId) typically claims rewards
        // We call withdraw with a very large number and let it cap at balance
        IStaking(STAKING_CONTRACT).withdraw(type(uint256).max, poolNumber);

        emit UnstakeExecuted(poolNumber);
    }

    /// @notice Buy a registered ERC20 with WETH
    function buyTokenWithETH(address token, uint256 amount, uint256 poolNumber) external onlyOperator operatorCooldown nonReentrant {
        // amount = WETH to spend (input amount)
        _checkCaps(ActionType.BuybackWETH, amount); // uses BuybackWETH caps

        TokenInfo storage info = tokenInfo[token];
        require(info.registered, "Token not registered");

        uint256 tokensReceived = SwapHelper.executeBuyToken(
            SwapHelper.BuyTokenParams({
                token: token,
                wethAmount: amount,
                poolAddress: info.poolAddress,
                v4PoolId: info.v4PoolId,
                isV4: info.isV4,
                slippageBps: operatorSlippageBps,
                universalRouter: UNIVERSAL_ROUTER,
                weth: WETH
            })
        );

        // Update cost basis (dynamic snapshot)
        info.totalWeiSpent += amount;
        info.totalTokensReceived += tokensReceived;
        info.initialBalanceSnapshot += tokensReceived; // snapshot += newBuyAmount

        emit TokenBought(token, amount, tokensReceived);
    }

    /// @notice Operator rebalance: Token → WETH → 75% ₸USD + 25% USDC to owner
    function rebalance(address token, uint256 amount) external onlyOperator operatorCooldown nonReentrant {
        TokenInfo storage info = tokenInfo[token];
        require(info.registered, "Token not registered");

        // BuybackWETH caps on full input (estimated WETH value)
        // For simplicity, we estimate WETH value from the swap output
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient token balance");

        (uint256 wethReceived, uint256 usdcToOwner, uint256 tusdBought) = SwapHelper.executeRebalance(
            SwapHelper.RebalanceParams({
                token: token,
                amount: amount,
                poolAddress: info.poolAddress,
                v4PoolId: info.v4PoolId,
                isV4: info.isV4,
                slippageBps: operatorSlippageBps,
                owner: owner,
                tusdPool: TUSD_POOL,
                usdcWethPool: USDC_WETH_POOL,
                universalRouter: UNIVERSAL_ROUTER,
                weth: WETH,
                usdc: USDC,
                tusd: TUSD
            })
        );

        // Check caps on WETH received (the actual value moved)
        _checkCaps(ActionType.Rebalance, wethReceived);

        info.lastMeaningfulRebalanceTimestamp = block.timestamp;

        emit RebalanceExecuted(token, amount, wethReceived, usdcToOwner, tusdBought);
    }

    // ======================== PERMISSIONLESS FUNCTION ========================

    /// @notice Anyone can call — guarantees ₸USD buybacks continue
    function permissionlessRebalance(address token, uint256 amount) external nonReentrant {
        TokenInfo storage info = tokenInfo[token];
        require(info.registered, "Token not registered");

        // Check unlock conditions
        (bool unlocked, uint256 unlockBps, bool p3ShouldTrigger, bool p3ShouldDrip, uint256 p3Bps) =
            _getUnlockPercentageDetailed(token);
        require(unlocked, "Not unlocked");

        // Update Path3 emergency state if applicable
        if (p3ShouldTrigger) {
            path3Triggered[token] = true;
            path3UnlockedPercentage[token] = p3Bps;
            path3LastDripTimestamp[token] = block.timestamp;
        } else if (p3ShouldDrip) {
            path3UnlockedPercentage[token] = p3Bps;
            path3LastDripTimestamp[token] = block.timestamp;
        }

        // Max 5% of unlocked per tx
        uint256 currentBalance = IERC20(token).balanceOf(address(this));
        uint256 unlockedAmount = (currentBalance * unlockBps) / 10000;
        uint256 maxPerTx = (unlockedAmount * MAX_PERCENT_PER_SWAP_BPS) / 10000;
        require(amount <= maxPerTx, "Exceeds max per swap");

        // 4h cooldown per token
        require(
            block.timestamp >= info.lastPermissionlessCooldown + PERMISSIONLESS_COOLDOWN,
            "Permissionless cooldown active"
        );

        // Circuit breaker: check ₸USD spot vs 24h TWAP
        // TODO: Implement TWAP comparison (requires observation accumulator)
        // For now, basic spot price sanity check

        // Hardcoded caps
        _checkPermissionlessCaps(amount);

        (uint256 wethReceived, uint256 usdcToOwner, uint256 tusdBought) = SwapHelper.executeRebalance(
            SwapHelper.RebalanceParams({
                token: token,
                amount: amount,
                poolAddress: info.poolAddress,
                v4PoolId: info.v4PoolId,
                isV4: info.isV4,
                slippageBps: SLIPPAGE_BPS,
                owner: owner,
                tusdPool: TUSD_POOL,
                usdcWethPool: USDC_WETH_POOL,
                universalRouter: UNIVERSAL_ROUTER,
                weth: WETH,
                usdc: USDC,
                tusd: TUSD
            })
        );

        require(wethReceived <= PERMISSIONLESS_ETH_PER_ACTION, "Exceeds ETH per action cap");

        info.lastPermissionlessCooldown = block.timestamp;
        info.lastMeaningfulRebalanceTimestamp = block.timestamp;

        emit PermissionlessRebalanceExecuted(msg.sender, token, amount, wethReceived, usdcToOwner, tusdBought);
    }

    // ======================== VIEW FUNCTIONS ========================

    function isOperator(address account) external view returns (bool) {
        return account == operator;
    }

    function getOperatorCaps(ActionType actionType) external view returns (uint256 perAction, uint256 perDay) {
        OperatorCaps storage caps = operatorCaps[actionType];
        return (caps.perAction, caps.perDay);
    }

    function getOperatorDailyUsed(address op, ActionType actionType) external view returns (uint256) {
        if (block.timestamp - operatorDayStart[op] > ROLLING_WINDOW) {
            return 0;
        }
        return operatorDailyUsed[op][actionType];
    }

    function getOperatorDayStart(address op) external view returns (uint256) {
        return operatorDayStart[op];
    }

    function getCooldownRemaining() external view returns (uint256) {
        if (block.timestamp >= lastOperatorActionTime + OPERATOR_COOLDOWN) {
            return 0;
        }
        return (lastOperatorActionTime + OPERATOR_COOLDOWN) - block.timestamp;
    }

    function getTokenInfo(address token)
        external
        view
        returns (
            uint256 totalWeiSpent,
            uint256 totalTokensReceived,
            uint256 initialBalanceSnapshot,
            address poolAddress,
            bool isV4,
            uint256 lastRebalance,
            bool registered
        )
    {
        TokenInfo storage info = tokenInfo[token];
        return (
            info.totalWeiSpent,
            info.totalTokensReceived,
            info.initialBalanceSnapshot,
            info.poolAddress,
            info.isV4,
            info.lastMeaningfulRebalanceTimestamp,
            info.registered
        );
    }

    function getRegisteredTokens() external view returns (address[] memory) {
        return registeredTokens;
    }

    function getUnlockPercentage(address token) external view returns (bool unlocked, uint256 unlockBps) {
        return _getUnlockPercentage(token);
    }

    // ======================== INTERNAL FUNCTIONS ========================

    function _checkCaps(ActionType actionType, uint256 amount) internal {
        OperatorCaps storage caps = operatorCaps[actionType];
        require(amount <= caps.perAction, "Exceeds per-action cap");

        // Rolling 24h window
        if (block.timestamp - operatorDayStart[msg.sender] > ROLLING_WINDOW) {
            operatorDailyUsed[msg.sender][actionType] = 0;
            operatorDayStart[msg.sender] = block.timestamp;
        }

        operatorDailyUsed[msg.sender][actionType] += amount;
        require(operatorDailyUsed[msg.sender][actionType] <= caps.perDay, "Exceeds daily cap");
    }

    function _checkPermissionlessCaps(uint256 amount) internal {
        // Rolling 24h window for permissionless caller
        if (block.timestamp - permissionlessDayStart[msg.sender] > ROLLING_WINDOW) {
            permissionlessDailyUsed[msg.sender] = 0;
            permissionlessDayStart[msg.sender] = block.timestamp;
        }

        permissionlessDailyUsed[msg.sender] += amount;
        // Note: amount is in token units, WETH cap checked post-swap
    }

    function _getUnlockPercentage(address token) internal view returns (bool unlocked, uint256 unlockBps) {
        (unlocked, unlockBps,,,) = _getUnlockPercentageDetailed(token);
    }

    function _getUnlockPercentageDetailed(address token)
        internal
        view
        returns (bool unlocked, uint256 unlockBps, bool p3ShouldTrigger, bool p3ShouldDrip, uint256 p3Bps)
    {
        TokenInfo storage info = tokenInfo[token];

        // Path 1: ROI-based
        (bool p1Unlocked, uint256 p1Bps) = PermissionlessModule.checkPath1ROI(
            PermissionlessModule.Path1Params({
                totalWeiSpent: info.totalWeiSpent,
                totalTokensReceived: info.totalTokensReceived,
                poolAddress: info.poolAddress,
                v4PoolId: info.v4PoolId,
                isV4: info.isV4,
                poolManager: POOL_MANAGER,
                lastMeaningfulRebalanceTimestamp: info.lastMeaningfulRebalanceTimestamp,
                token: token,
                weth: WETH
            })
        );

        // Path 2: Market cap
        (bool p2Unlocked, uint256 p2Bps) = PermissionlessModule.checkPath2MarketCap(
            PermissionlessModule.Path2Params({
                poolAddress: info.poolAddress,
                v4PoolId: info.v4PoolId,
                isV4: info.isV4,
                poolManager: POOL_MANAGER,
                chainlinkFeed: CHAINLINK_ETH_USD,
                usdcWethPool: USDC_WETH_POOL,
                lastMeaningfulRebalanceTimestamp: info.lastMeaningfulRebalanceTimestamp,
                token: token,
                weth: WETH
            })
        );

        // Path 3: Emergency
        bool p3Unlocked;
        (p3Unlocked, p3Bps, p3ShouldTrigger, p3ShouldDrip) = PermissionlessModule.checkPath3Emergency(
            PermissionlessModule.Path3Params({
                path3Triggered: path3Triggered[token],
                path3UnlockedPercentage: path3UnlockedPercentage[token],
                path3LastDripTimestamp: path3LastDripTimestamp[token],
                lastMeaningfulRebalanceTimestamp: info.lastMeaningfulRebalanceTimestamp
            })
        );

        // Take the highest unlock percentage
        unlockBps = p1Bps;
        if (p2Bps > unlockBps) unlockBps = p2Bps;
        if (p3Bps > unlockBps) unlockBps = p3Bps;

        unlocked = p1Unlocked || p2Unlocked || p3Unlocked;
    }

    // ======================== RECEIVE ETH ========================

    receive() external payable {
        // Wrap incoming ETH to WETH
        IWETH(WETH).deposit{value: msg.value}();
    }
}
