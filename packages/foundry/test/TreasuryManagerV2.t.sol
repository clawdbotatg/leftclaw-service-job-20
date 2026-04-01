// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/TreasuryManagerV2.sol";
import "../contracts/interfaces/IInterfaces.sol";

/// @dev Mock ERC20 for testing
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public _decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public _balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 __decimals) {
        name = _name;
        symbol = _symbol;
        _decimals = __decimals;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf[account];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balanceOf[msg.sender] >= amount, "Insufficient balance");
        _balanceOf[msg.sender] -= amount;
        _balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        _balanceOf[from] -= amount;
        _balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balanceOf[to] += amount;
        totalSupply += amount;
    }
}

/// @dev Mock WETH for testing
contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped ETH", "WETH", 18) {}

    function deposit() external payable {
        _balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
    }

    function withdraw(uint256 wad) external {
        require(_balanceOf[msg.sender] >= wad, "Insufficient balance");
        _balanceOf[msg.sender] -= wad;
        totalSupply -= wad;
        payable(msg.sender).transfer(wad);
    }
}

/// @dev Mock Staking contract for testing
contract MockStaking {
    mapping(uint256 => mapping(address => uint256)) public stakedAmount;
    address public stakingToken;

    constructor(address _stakingToken) {
        stakingToken = _stakingToken;
    }

    function deposit(uint256 _amount, uint256 poolId) external {
        IERC20(stakingToken).transferFrom(msg.sender, address(this), _amount);
        stakedAmount[poolId][msg.sender] += _amount;
    }

    function withdraw(uint256 _amount, uint256 poolId) external {
        uint256 staked = stakedAmount[poolId][msg.sender];
        uint256 toWithdraw = _amount > staked ? staked : _amount;
        if (toWithdraw > 0) {
            stakedAmount[poolId][msg.sender] -= toWithdraw;
            IERC20(stakingToken).transfer(msg.sender, toWithdraw);
        }
    }

    function poolInfo(uint256)
        external
        pure
        returns (
            address,
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            address
        )
    {
        return (address(0), address(0), 0, 0, 0, 0, 0, 0, 0, address(0));
    }
}

contract TreasuryManagerV2Test is Test {
    TreasuryManagerV2 public tm;
    MockWETH public weth;
    MockERC20 public usdc;
    MockERC20 public tusd;
    MockStaking public staking;

    address public owner = address(0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506);
    address public operatorAddr = address(0xABCD);
    address public user = address(0x1234);
    address public universalRouter = address(0x5555);
    address public poolManager = address(0x6666);
    address public tusdPool = address(0x7777);
    address public usdcWethPool = address(0x8888);
    address public chainlinkFeed = address(0x9999);

    function setUp() public {
        // Set a reasonable block.timestamp (Foundry defaults to 1)
        vm.warp(1_700_000_000);

        weth = new MockWETH();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        tusd = new MockERC20("TurboUSD", "TUSD", 18);

        staking = new MockStaking(address(tusd));

        tm = new TreasuryManagerV2(
            owner,
            address(weth),
            address(usdc),
            address(tusd),
            address(staking),
            universalRouter,
            poolManager,
            tusdPool,
            usdcWethPool,
            chainlinkFeed
        );

        // Set operator
        vm.prank(owner);
        tm.setOperator(operatorAddr);
    }

    // ======================== OWNERSHIP TESTS ========================

    function test_OwnerIsClient() public view {
        assertEq(tm.owner(), owner);
    }

    function test_TransferOwnership() public {
        address newOwner = address(0xBEEF);
        vm.prank(owner);
        tm.transferOwnership(newOwner);
        assertEq(tm.owner(), newOwner);
    }

    function test_TransferOwnershipNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        tm.transferOwnership(user);
    }

    function test_TransferOwnershipZero() public {
        vm.prank(owner);
        vm.expectRevert("Zero address");
        tm.transferOwnership(address(0));
    }

    // ======================== OPERATOR TESTS ========================

    function test_SetOperator() public {
        vm.prank(owner);
        tm.setOperator(user);
        assertEq(tm.operator(), user);
    }

    function test_SetOperatorNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        tm.setOperator(user);
    }

    function test_IsOperator() public view {
        assertTrue(tm.isOperator(operatorAddr));
        assertFalse(tm.isOperator(user));
    }

    // ======================== CAPS TESTS ========================

    function test_DefaultCaps() public view {
        (uint256 perAction, uint256 perDay) = tm.getOperatorCaps(TreasuryManagerV2.ActionType.BuybackWETH);
        assertEq(perAction, 0.5 ether);
        assertEq(perDay, 2 ether);
    }

    function test_UpdateCaps() public {
        vm.prank(owner);
        tm.updateCaps(TreasuryManagerV2.ActionType.BuybackWETH, 1 ether, 5 ether);
        (uint256 perAction, uint256 perDay) = tm.getOperatorCaps(TreasuryManagerV2.ActionType.BuybackWETH);
        assertEq(perAction, 1 ether);
        assertEq(perDay, 5 ether);
    }

    function test_UpdateCapsInvalid() public {
        vm.prank(owner);
        vm.expectRevert("perAction > perDay");
        tm.updateCaps(TreasuryManagerV2.ActionType.BuybackWETH, 5 ether, 1 ether);
    }

    function test_UpdateCapsNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        tm.updateCaps(TreasuryManagerV2.ActionType.BuybackWETH, 1 ether, 5 ether);
    }

    // ======================== SLIPPAGE TESTS ========================

    function test_DefaultSlippage() public view {
        assertEq(tm.operatorSlippageBps(), 300);
    }

    function test_SetSlippage() public {
        vm.prank(owner);
        tm.setSlippage(500);
        assertEq(tm.operatorSlippageBps(), 500);
    }

    function test_SetSlippageInvalid() public {
        vm.prank(owner);
        vm.expectRevert("Invalid slippage");
        tm.setSlippage(0);

        vm.prank(owner);
        vm.expectRevert("Invalid slippage");
        tm.setSlippage(1001);
    }

    // ======================== STAKING TESTS ========================

    function test_Stake() public {
        uint256 amount = 1000e18;
        tusd.mint(address(tm), amount);

        vm.prank(operatorAddr);
        tm.stake(amount, 0);

        assertEq(staking.stakedAmount(0, address(tm)), amount);
        assertEq(tusd.balanceOf(address(tm)), 0);
    }

    function test_StakeInsufficientBalance() public {
        vm.prank(operatorAddr);
        vm.expectRevert("Insufficient TUSD");
        tm.stake(1000e18, 0);
    }

    function test_StakeExceedsPerActionCap() public {
        uint256 amount = 200_000_000e18; // Over 100M per-action cap
        tusd.mint(address(tm), amount);

        vm.prank(operatorAddr);
        vm.expectRevert("Exceeds per-action cap");
        tm.stake(amount, 0);
    }

    function test_StakeMultiplePools() public {
        tusd.mint(address(tm), 2000e18);

        vm.prank(operatorAddr);
        tm.stake(1000e18, 0);

        // Wait for cooldown
        vm.warp(block.timestamp + 61 minutes);

        vm.prank(operatorAddr);
        tm.stake(1000e18, 3);

        assertEq(staking.stakedAmount(0, address(tm)), 1000e18);
        assertEq(staking.stakedAmount(3, address(tm)), 1000e18);
    }

    function test_StakeCooldown() public {
        tusd.mint(address(tm), 2000e18);

        vm.prank(operatorAddr);
        tm.stake(1000e18, 0);

        // Try again immediately — should fail
        vm.prank(operatorAddr);
        vm.expectRevert("Operator cooldown active");
        tm.stake(1000e18, 1);
    }

    function test_StakeDailyCap() public {
        // Stake cap: 100M per action, 500M per day
        tusd.mint(address(tm), 600_000_000e18);

        // Start at a clean timestamp
        uint256 start = block.timestamp + 2 hours;
        vm.warp(start);

        // Stake 100M five times (reaching daily cap of 500M)
        for (uint256 i = 0; i < 5; i++) {
            if (i > 0) vm.warp(block.timestamp + 61 minutes);
            vm.prank(operatorAddr);
            tm.stake(100_000_000e18, 0);
        }

        // 6th should fail
        vm.warp(block.timestamp + 61 minutes);
        vm.prank(operatorAddr);
        vm.expectRevert("Exceeds daily cap");
        tm.stake(100_000_000e18, 0);
    }

    function test_StakeDailyCapResets() public {
        tusd.mint(address(tm), 600_000_000e18);

        // Start at a clean timestamp
        uint256 start = block.timestamp + 2 hours;
        vm.warp(start);

        // Use up daily cap
        for (uint256 i = 0; i < 5; i++) {
            if (i > 0) vm.warp(block.timestamp + 61 minutes);
            vm.prank(operatorAddr);
            tm.stake(100_000_000e18, 0);
        }

        // Advance past 24h
        vm.warp(block.timestamp + 25 hours);

        // Should work again
        vm.prank(operatorAddr);
        tm.stake(100_000_000e18, 0);

        assertEq(tm.getOperatorDailyUsed(operatorAddr, TreasuryManagerV2.ActionType.Stake), 100_000_000e18);
    }

    // ======================== UNSTAKE TESTS ========================

    function test_Unstake() public {
        uint256 amount = 1000e18;
        tusd.mint(address(tm), amount);

        vm.prank(operatorAddr);
        tm.stake(amount, 0);

        assertEq(staking.stakedAmount(0, address(tm)), amount);

        // Unstake — no cooldown needed
        vm.prank(operatorAddr);
        tm.unstake(0);

        assertEq(staking.stakedAmount(0, address(tm)), 0);
        assertEq(tusd.balanceOf(address(tm)), amount);
    }

    function test_UnstakeNoCooldownRequired() public {
        tusd.mint(address(tm), 1000e18);

        vm.prank(operatorAddr);
        tm.stake(1000e18, 0);

        // Unstake immediately — no cooldown
        vm.prank(operatorAddr);
        tm.unstake(0);

        assertEq(tusd.balanceOf(address(tm)), 1000e18);
    }

    function test_UnstakeNotOperator() public {
        vm.prank(user);
        vm.expectRevert("Not operator");
        tm.unstake(0);
    }

    function test_UnstakeEmptyPool() public {
        // Unstaking from pool with 0 balance should still work
        vm.prank(operatorAddr);
        tm.unstake(5);
        // No revert — just withdraws 0
    }

    // ======================== BURN TESTS ========================

    function test_Burn() public {
        uint256 amount = 1000e18;
        tusd.mint(address(tm), amount);

        vm.prank(operatorAddr);
        tm.burn(amount);

        assertEq(tusd.balanceOf(address(tm)), 0);
        assertEq(tusd.balanceOf(address(0xdead)), amount);
    }

    function test_BurnInsufficientBalance() public {
        vm.prank(operatorAddr);
        vm.expectRevert("Insufficient TUSD");
        tm.burn(1000e18);
    }

    function test_BurnNotOperator() public {
        tusd.mint(address(tm), 1000e18);
        vm.prank(user);
        vm.expectRevert("Not operator");
        tm.burn(1000e18);
    }

    // ======================== TOKEN REGISTRATION TESTS ========================

    function test_RegisterToken() public {
        address token = address(0xAAAA);
        vm.prank(operatorAddr);
        tm.registerToken(token, address(0xBBBB), bytes32(0), false);

        (,,,address pool, bool isV4,, bool registered) = tm.getTokenInfo(token);
        assertTrue(registered);
        assertEq(pool, address(0xBBBB));
        assertFalse(isV4);
    }

    function test_RegisterTokenDuplicate() public {
        address token = address(0xAAAA);
        vm.prank(operatorAddr);
        tm.registerToken(token, address(0xBBBB), bytes32(0), false);

        vm.prank(operatorAddr);
        vm.expectRevert("Already registered");
        tm.registerToken(token, address(0xBBBB), bytes32(0), false);
    }

    function test_GetRegisteredTokens() public {
        vm.startPrank(operatorAddr);
        tm.registerToken(address(0xAA), address(0), bytes32(0), false);
        tm.registerToken(address(0xBB), address(0), bytes32(0), false);
        vm.stopPrank();

        address[] memory tokens = tm.getRegisteredTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(0xAA));
        assertEq(tokens[1], address(0xBB));
    }

    // ======================== COOLDOWN TESTS ========================

    function test_CooldownRemaining() public {
        tusd.mint(address(tm), 1000e18);

        vm.prank(operatorAddr);
        tm.stake(1000e18, 0);

        uint256 remaining = tm.getCooldownRemaining();
        assertGt(remaining, 0);
        assertLe(remaining, 60 minutes);

        // Advance past cooldown
        vm.warp(block.timestamp + 61 minutes);
        assertEq(tm.getCooldownRemaining(), 0);
    }

    // ======================== RECEIVE ETH TEST ========================

    function test_ReceiveETH() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool success,) = address(tm).call{value: 1 ether}("");
        assertTrue(success);

        // ETH should be wrapped to WETH
        assertEq(weth.balanceOf(address(tm)), 1 ether);
    }

    // ======================== DEAD POOL RESCUE TESTS ========================

    function test_RescueDeadPoolToken() public {
        MockERC20 token = new MockERC20("Test", "TST", 18);
        token.mint(address(tm), 1000e18);

        vm.prank(operatorAddr);
        tm.registerToken(address(token), address(0xBBBB), bytes32(0), false);

        // Simulate a rebalance timestamp in the past
        // We need to use buyTokenWithETH to set lastMeaningfulRebalanceTimestamp
        // For this test, we'll just check the require conditions

        // Can't rescue if not dead yet (no rebalance timestamp set)
        vm.prank(owner);
        vm.expectRevert("Pool not dead");
        tm.rescueDeadPoolToken(address(token));
    }

    function test_RescueNotRegistered() public {
        vm.prank(owner);
        vm.expectRevert("Token not registered");
        tm.rescueDeadPoolToken(address(0xAAAA));
    }

    // ======================== IMMUTABLE CONSTANTS TESTS ========================

    function test_ImmutableConstants() public view {
        assertEq(tm.SLIPPAGE_BPS(), 300);
        assertEq(tm.PERMISSIONLESS_COOLDOWN(), 4 hours);
        assertEq(tm.MAX_PERCENT_PER_SWAP_BPS(), 500);
        assertEq(tm.CIRCUIT_BREAKER_BPS(), 1500);
        assertEq(tm.OPERATOR_INACTIVITY_PERIOD(), 14 days);
        assertEq(tm.DEAD_POOL_THRESHOLD(), 90 days);
        assertEq(tm.OPERATOR_COOLDOWN(), 60 minutes);
        assertEq(tm.PERMISSIONLESS_ETH_PER_ACTION(), 0.5 ether);
        assertEq(tm.PERMISSIONLESS_ETH_PER_DAY(), 2 ether);
        assertEq(tm.ROLLING_WINDOW(), 24 hours);
    }

    // ======================== CONSTRUCTOR TESTS ========================

    function test_ConstructorZeroOwner() public {
        vm.expectRevert("Zero owner");
        new TreasuryManagerV2(
            address(0),
            address(weth),
            address(usdc),
            address(tusd),
            address(staking),
            universalRouter,
            poolManager,
            tusdPool,
            usdcWethPool,
            chainlinkFeed
        );
    }

    function test_ConstructorAddresses() public view {
        assertEq(tm.WETH(), address(weth));
        assertEq(tm.USDC(), address(usdc));
        assertEq(tm.TUSD(), address(tusd));
        assertEq(tm.STAKING_CONTRACT(), address(staking));
        assertEq(tm.UNIVERSAL_ROUTER(), universalRouter);
        assertEq(tm.POOL_MANAGER(), poolManager);
    }
}
