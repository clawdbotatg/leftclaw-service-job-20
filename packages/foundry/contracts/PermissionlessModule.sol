// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interfaces/IInterfaces.sol";

/// @title PermissionlessModule — Pure library for unlock path calculations and oracle reads
/// @notice All functions are internal. Handles unlock path math and price feeds.
/// @dev Called via delegatecall from TreasuryManager
library PermissionlessModule {
    uint256 constant ROI_THRESHOLD = 10000; // 1000% in bps (10x)
    uint256 constant MARKET_CAP_THRESHOLD = 100_000_000e18; // $100M
    uint256 constant ASSUMED_SUPPLY = 100_000_000_000e18; // 100B
    uint256 constant INACTIVITY_WINDOW = 14 days;
    uint256 constant PATH3_INITIAL_DELAY = 180 days;
    uint256 constant PATH3_DRIP_INTERVAL = 60 days;
    uint256 constant PATH3_DRIP_PERCENTAGE = 500; // 5% in bps

    struct Path1Params {
        uint256 totalWeiSpent;
        uint256 totalTokensReceived;
        address poolAddress;
        bytes32 v4PoolId;
        bool isV4;
        address poolManager;
        uint256 lastMeaningfulRebalanceTimestamp;
        address token;
        address weth;
    }

    struct Path2Params {
        address poolAddress;
        bytes32 v4PoolId;
        bool isV4;
        address poolManager;
        address chainlinkFeed;
        address usdcWethPool;
        uint256 lastMeaningfulRebalanceTimestamp;
        address token;
        address weth;
    }

    struct Path3Params {
        bool path3Triggered;
        uint256 path3UnlockedPercentage;
        uint256 path3LastDripTimestamp;
        uint256 lastMeaningfulRebalanceTimestamp;
    }

    struct SpotPriceParams {
        address poolAddress;
        bytes32 v4PoolId;
        bool isV4;
        address poolManager;
        address token;
        address weth;
    }

    /// @notice Path 1: ROI-based unlock
    /// @dev Base 25% at 1000% ROI, then 5% of remaining per each additional 10% ROI (compounding)
    function checkPath1ROI(Path1Params memory params)
        internal
        view
        returns (bool unlocked, uint256 unlockPercentageBps)
    {
        if (params.totalWeiSpent == 0 || params.totalTokensReceived == 0) {
            return (false, 0);
        }

        // Average cost per token in WETH
        // avgCost = totalWeiSpent * 1e18 / totalTokensReceived (scaled by 1e18)
        uint256 avgCost = (params.totalWeiSpent * 1e18) / params.totalTokensReceived;

        // Current spot price
        uint256 currentPrice = getSpotPriceInWETH(
            SpotPriceParams({
                poolAddress: params.poolAddress,
                v4PoolId: params.v4PoolId,
                isV4: params.isV4,
                poolManager: params.poolManager,
                token: params.token,
                weth: params.weth
            })
        );

        if (currentPrice <= avgCost) {
            return (false, 0);
        }

        // ROI in bps: ((currentPrice - avgCost) * 10000) / avgCost
        uint256 roi = ((currentPrice - avgCost) * 10000) / avgCost;

        if (roi < ROI_THRESHOLD) {
            return (false, 0);
        }

        // Check inactivity
        if (
            params.lastMeaningfulRebalanceTimestamp > 0
                && block.timestamp - params.lastMeaningfulRebalanceTimestamp < INACTIVITY_WINDOW
        ) {
            return (false, 0);
        }

        // Base unlock at 1000% ROI: 25% (2500 bps)
        unlockPercentageBps = 2500;

        // Additional tranches: each 10% ROI above 1000% = 5% of remaining locked (compounding)
        uint256 additionalTranches = (roi - ROI_THRESHOLD) / 1000;

        // Compound: each tranche unlocks 5% of remaining locked
        // remaining locked starts at 7500 bps (10000 - 2500)
        uint256 remainingLocked = 7500;
        for (uint256 i = 0; i < additionalTranches && i < 200; i++) {
            uint256 trancheUnlock = (remainingLocked * 500) / 10000; // 5% of remaining
            unlockPercentageBps += trancheUnlock;
            remainingLocked -= trancheUnlock;
        }

        // Cap at 100%
        if (unlockPercentageBps > 10000) {
            unlockPercentageBps = 10000;
        }

        return (true, unlockPercentageBps);
    }

    /// @notice Path 2: Market cap-based unlock
    /// @dev Base 20% at $100M, then flat 5% per each additional 10% market cap
    function checkPath2MarketCap(Path2Params memory params)
        internal
        view
        returns (bool unlocked, uint256 unlockPercentageBps)
    {
        // Get token spot price in WETH
        uint256 spotPriceInWETH = getSpotPriceInWETH(
            SpotPriceParams({
                poolAddress: params.poolAddress,
                v4PoolId: params.v4PoolId,
                isV4: params.isV4,
                poolManager: params.poolManager,
                token: params.token,
                weth: params.weth
            })
        );

        // Get ETH/USD price
        uint256 ethUsdPrice = getETHUSDPrice(params.chainlinkFeed, params.usdcWethPool);

        // Market cap = spotPriceInWETH * ethUsdPrice * ASSUMED_SUPPLY / 1e18 / 1e18
        // spotPriceInWETH is WETH per token (1e18 scaled)
        // ethUsdPrice is USD per ETH (1e18 scaled)
        uint256 marketCap = (spotPriceInWETH * ethUsdPrice * (ASSUMED_SUPPLY / 1e18)) / 1e18 / 1e18;

        if (marketCap < MARKET_CAP_THRESHOLD) {
            return (false, 0);
        }

        // Check inactivity
        if (
            params.lastMeaningfulRebalanceTimestamp > 0
                && block.timestamp - params.lastMeaningfulRebalanceTimestamp < INACTIVITY_WINDOW
        ) {
            return (false, 0);
        }

        // Base unlock at $100M: 20% (2000 bps)
        unlockPercentageBps = 2000;

        // Additional tranches: each 10% above $100M = flat 5% (500 bps)
        // additionalTranches = ((marketCap - 100M) * 10000 / 100M) / 1000
        uint256 excessBps = ((marketCap - MARKET_CAP_THRESHOLD) * 10000) / MARKET_CAP_THRESHOLD;
        uint256 additionalTranches = excessBps / 1000;

        // Flat 5% per tranche (NOT compounding)
        unlockPercentageBps += additionalTranches * 500;

        // Cap at 100%
        if (unlockPercentageBps > 10000) {
            unlockPercentageBps = 10000;
        }

        return (true, unlockPercentageBps);
    }

    /// @notice Path 3: Emergency last resort
    /// @dev 180-day trigger, then 5% drip every 60 days
    function checkPath3Emergency(Path3Params memory params)
        internal
        view
        returns (bool unlocked, uint256 unlockPercentageBps, bool shouldTrigger, bool shouldDrip)
    {
        if (!params.path3Triggered) {
            // Phase 1: Pre-trigger
            if (
                params.lastMeaningfulRebalanceTimestamp > 0
                    && block.timestamp - params.lastMeaningfulRebalanceTimestamp >= PATH3_INITIAL_DELAY
            ) {
                // Should trigger: first 5% unlocks
                return (true, PATH3_DRIP_PERCENTAGE, true, false);
            }
            // Not yet triggered and inactivity not met
            if (params.lastMeaningfulRebalanceTimestamp == 0) {
                // No rebalance has ever happened - check from contract deployment
                // In this case path3 can't trigger yet (no reference point)
                return (false, 0, false, false);
            }
            return (false, 0, false, false);
        }

        // Phase 2: Drip
        unlockPercentageBps = params.path3UnlockedPercentage;

        if (block.timestamp - params.path3LastDripTimestamp >= PATH3_DRIP_INTERVAL) {
            uint256 newPercentage = unlockPercentageBps + PATH3_DRIP_PERCENTAGE;
            if (newPercentage > 10000) newPercentage = 10000;
            return (true, newPercentage, false, true);
        }

        // Already triggered but not time for next drip
        return (unlockPercentageBps > 0, unlockPercentageBps, false, false);
    }

    /// @notice Dual oracle ETH/USD price
    /// @dev Chainlink primary with staleness check, USDC/WETH pool fallback
    function getETHUSDPrice(address chainlinkFeed, address usdcWethPool) internal view returns (uint256) {
        // Primary: Chainlink
        try IAggregatorV3(chainlinkFeed).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            if (answeredInRound >= roundId && updatedAt >= block.timestamp - 1 hours && answer > 0) {
                // Chainlink returns 8 decimals, normalize to 18
                return uint256(answer) * 1e10;
            }
        } catch {}

        // Fallback: USDC/WETH pool
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(usdcWethPool).slot0();
        address token0 = IUniswapV3Pool(usdcWethPool).token0();

        // USDC has 6 decimals, WETH has 18 decimals
        // sqrtPriceX96 = sqrt(price) * 2^96
        // price = (sqrtPriceX96 / 2^96)^2
        uint256 sqrtPrice = uint256(sqrtPriceX96);

        if (token0 == usdcWethPool) {
            // This shouldn't happen, token0 should be USDC or WETH address
            revert("Invalid pool config");
        }

        // Price = sqrtPriceX96^2 / 2^192
        // If USDC is token0: price = WETH/USDC (how much USDC per WETH)
        // If WETH is token0: price = USDC/WETH (how much WETH per USDC), so ETH/USD = 1/price

        uint256 price;
        // USDC (0x833589...) < WETH (0x420000...) on Base? Let's check at runtime
        // Actually on Base: USDC = 0x833589... and WETH = 0x420000...
        // 0x420... < 0x833... so WETH is token0
        // When WETH is token0: sqrtPriceX96 represents price of token1/token0 = USDC/WETH
        // But USDC has 6 decimals, WETH has 18
        // Actual price = (sqrtPriceX96^2 / 2^192) * 10^(18-6) = (sqrtPriceX96^2 / 2^192) * 10^12

        // We need ETH price in USD with 18 decimals
        // sqrtPriceX96^2 = priceX192 (Q192.0)
        // price in USDC per WETH = priceX192 / 2^192 * 10^(18-6)
        // Then scale to 18 decimals: price * 10^12

        // Safe math: sqrtPrice^2 can overflow if > 2^128
        // sqrtPriceX96 for ETH/USDC should be around 3.6e24, safe for squaring in uint256

        if (sqrtPrice > type(uint128).max) {
            // Use bit shifting to avoid overflow
            price = (sqrtPrice >> 96) * (sqrtPrice >> 96);
        } else {
            price = (sqrtPrice * sqrtPrice) >> 192;
        }

        // Adjust for decimal difference (USDC 6, WETH 18)
        // If WETH is token0, price = USDC per WETH (in USDC base units per WETH base unit)
        // Scale to 18 decimals: multiply by 1e12
        // The result should give ETH/USD price in 18 decimal format
        address weth = address(0x4200000000000000000000000000000000000006);
        if (token0 == weth) {
            // price is USDC-base-units per WETH-base-unit
            // To get USD with 18 decimals: price * 1e12 * 1e18 / 1e0
            // Actually: price already in units of 10^(-6) USDC per 10^(-18) WETH
            // = price * 10^(-6+18) USDC per WETH = price * 10^12
            price = price * 1e12;
        } else {
            // USDC is token0, price = WETH-base-units per USDC-base-unit
            // ETH/USD = 1/price adjusted for decimals
            // price is in units of 10^(-18) WETH per 10^(-6) USDC = price * 10^(-12) WETH per USDC
            // ETH/USD = 10^12 / price (in USDC per WETH)
            // Scale to 18 decimals
            if (price == 0) revert("Zero price");
            price = (1e30) / price; // 1e18 * 1e12 / price
        }

        require(price > 0, "ETH/USD price zero");
        return price;
    }

    /// @notice Get spot price of token in WETH
    /// @dev V3: slot0 read, V4: getSlot0 read. Handles token ordering.
    function getSpotPriceInWETH(SpotPriceParams memory params) internal view returns (uint256) {
        uint160 sqrtPriceX96;
        address token0;

        if (params.isV4) {
            (sqrtPriceX96,,,) = IPoolManager(params.poolManager).getSlot0(params.v4PoolId);
            // For V4, determine token ordering
            token0 = params.token < params.weth ? params.token : params.weth;
        } else {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(params.poolAddress).slot0();
            token0 = IUniswapV3Pool(params.poolAddress).token0();
        }

        // Calculate price from sqrtPriceX96
        // price = (sqrtPriceX96 / 2^96)^2
        // This gives us token1/token0 ratio in base units

        uint256 sqrtPrice = uint256(sqrtPriceX96);

        // We want: WETH amount per 1 token (1e18 of token)
        // This is the "price" of the token in WETH terms

        if (token0 == params.token) {
            // price = token1/token0 = WETH/token
            // sqrtPriceX96^2 / 2^192 = WETH(base) per token(base)
            // For 1e18 token: pricePerToken = (sqrtPriceX96^2 / 2^192) * 1e18
            // But we need to handle token decimals

            // Assuming both 18 decimals:
            // price = sqrtPriceX96^2 * 1e18 / 2^192
            if (sqrtPrice > type(uint128).max) {
                return ((sqrtPrice >> 96) * (sqrtPrice >> 96) * 1e18) >> 0;
            } else {
                return (sqrtPrice * sqrtPrice * 1e18) >> 192;
            }
        } else {
            // token1 = token, token0 = WETH
            // price = token1/token0 = token/WETH
            // We want WETH per token = 1/price
            // = 2^192 / (sqrtPriceX96^2)

            if (sqrtPrice == 0) return 0;

            if (sqrtPrice > type(uint128).max) {
                uint256 priceSquared = (sqrtPrice >> 96) * (sqrtPrice >> 96);
                if (priceSquared == 0) return 0;
                return 1e18 / priceSquared;
            } else {
                // 1e18 * 2^192 / sqrtPrice^2
                // To avoid overflow, use: (1e18 << 192) / (sqrtPrice * sqrtPrice)
                // This is too large for uint256. Instead:
                // price_token_per_weth = sqrtPrice^2 / 2^192 (with decimals)
                // price_weth_per_token = 2^192 / sqrtPrice^2 (with decimals)
                // = (2^96/sqrtPrice)^2
                uint256 inverseSqrt = (uint256(1) << 96) * 1e9 / sqrtPrice;
                return (inverseSqrt * inverseSqrt) / 1; // result in 1e18
            }
        }
    }
}
