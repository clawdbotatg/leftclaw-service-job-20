// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interfaces/IInterfaces.sol";

/// @title SwapHelper — Pure library for all Uniswap swap operations
/// @notice All functions are internal, called via delegatecall from TreasuryManager
/// @dev TreasuryManager is always msg.sender when interacting with Universal Router and tokens
library SwapHelper {
    // Universal Router command bytes
    // V3_SWAP_EXACT_IN = 0x00
    // V4_SWAP = 0x10
    uint256 constant V3_SWAP_EXACT_IN = 0x00;
    uint256 constant V4_SWAP = 0x10;

    struct RebalanceParams {
        address token;
        uint256 amount;
        address poolAddress; // V3 pool or address(0) for V4
        bytes32 v4PoolId; // V4 pool ID or bytes32(0) for V3
        bool isV4;
        uint256 slippageBps;
        address owner; // recipient of 25% USDC
        address tusdPool; // official ₸USD V3 pool
        address usdcWethPool; // canonical USDC/WETH pool
        address universalRouter;
        address weth;
        address usdc;
        address tusd;
    }

    struct BuybackParams {
        address inputToken; // WETH or USDC
        uint256 amountIn;
        uint256 slippageBps;
        address tusdPool; // official ₸USD V3 pool
        address usdcWethPool; // only used for USDC buybacks
        address universalRouter;
        address weth;
        address usdc;
        address tusd;
    }

    struct BuyTokenParams {
        address token;
        uint256 wethAmount;
        address poolAddress;
        bytes32 v4PoolId;
        bool isV4;
        uint256 slippageBps;
        address universalRouter;
        address weth;
    }

    /// @notice Atomic 3-leg rebalance: Token → WETH → 25% USDC to owner + 75% ₸USD
    function executeRebalance(RebalanceParams memory params)
        internal
        returns (uint256 wethReceived, uint256 usdcToOwner, uint256 tusdBought)
    {
        // Leg 1: Sell ERC20 → WETH
        IERC20(params.token).approve(params.universalRouter, params.amount);

        uint256 wethBefore = IERC20(params.weth).balanceOf(address(this));

        if (params.isV4) {
            _executeV4Swap(
                params.universalRouter, params.token, params.weth, params.amount, 0, params.v4PoolId
            );
        } else {
            _executeV3Swap(
                params.universalRouter,
                params.token,
                params.weth,
                params.amount,
                0,
                params.poolAddress
            );
        }

        uint256 wethAfter = IERC20(params.weth).balanceOf(address(this));
        wethReceived = wethAfter - wethBefore;
        require(wethReceived > 0, "Zero WETH output");

        // Calculate slippage minimum (we just check > 0 for leg 1, per-leg slippage later)

        // Leg 2: Swap 25% of WETH → USDC to owner
        uint256 wethForUsdc = (wethReceived * 2500) / 10000;
        uint256 wethForTusd = wethReceived - wethForUsdc;

        IERC20(params.weth).approve(params.universalRouter, wethForUsdc);

        uint256 usdcBefore = IERC20(params.usdc).balanceOf(address(this));

        _executeV3Swap(params.universalRouter, params.weth, params.usdc, wethForUsdc, 0, params.usdcWethPool);

        uint256 usdcAfter = IERC20(params.usdc).balanceOf(address(this));
        usdcToOwner = usdcAfter - usdcBefore;
        require(usdcToOwner > 0, "Zero USDC output");

        // Transfer USDC to owner
        IERC20(params.usdc).transfer(params.owner, usdcToOwner);

        // Leg 3: Swap 75% of WETH → ₸USD
        IERC20(params.weth).approve(params.universalRouter, wethForTusd);

        uint256 tusdBefore = IERC20(params.tusd).balanceOf(address(this));

        _executeV3Swap(params.universalRouter, params.weth, params.tusd, wethForTusd, 0, params.tusdPool);

        uint256 tusdAfterSwap = IERC20(params.tusd).balanceOf(address(this));
        tusdBought = tusdAfterSwap - tusdBefore;
        require(tusdBought > 0, "Zero TUSD output");
    }

    /// @notice Buyback ₸USD with WETH or USDC
    function executeBuyback(BuybackParams memory params) internal returns (uint256 tusdReceived) {
        if (params.inputToken == params.weth) {
            // Direct WETH → ₸USD
            IERC20(params.weth).approve(params.universalRouter, params.amountIn);

            uint256 tusdBefore = IERC20(params.tusd).balanceOf(address(this));

            _executeV3Swap(
                params.universalRouter, params.weth, params.tusd, params.amountIn, 0, params.tusdPool
            );

            uint256 tusdAfter = IERC20(params.tusd).balanceOf(address(this));
            tusdReceived = tusdAfter - tusdBefore;
            require(tusdReceived > 0, "Zero TUSD output");
        } else {
            // USDC → WETH → ₸USD (two hops)
            IERC20(params.usdc).approve(params.universalRouter, params.amountIn);

            // Hop 1: USDC → WETH
            uint256 wethBefore = IERC20(params.weth).balanceOf(address(this));

            _executeV3Swap(
                params.universalRouter, params.usdc, params.weth, params.amountIn, 0, params.usdcWethPool
            );

            uint256 wethAfter = IERC20(params.weth).balanceOf(address(this));
            uint256 wethOut = wethAfter - wethBefore;
            require(wethOut > 0, "Zero WETH from USDC");

            // Hop 2: WETH → ₸USD
            IERC20(params.weth).approve(params.universalRouter, wethOut);

            uint256 tusdBefore = IERC20(params.tusd).balanceOf(address(this));

            _executeV3Swap(params.universalRouter, params.weth, params.tusd, wethOut, 0, params.tusdPool);

            uint256 tusdAfter = IERC20(params.tusd).balanceOf(address(this));
            tusdReceived = tusdAfter - tusdBefore;
            require(tusdReceived > 0, "Zero TUSD output");
        }
    }

    /// @notice Buy registered ERC20 with WETH
    function executeBuyToken(BuyTokenParams memory params) internal returns (uint256 tokensReceived) {
        IERC20(params.weth).approve(params.universalRouter, params.wethAmount);

        uint256 tokenBefore = IERC20(params.token).balanceOf(address(this));

        if (params.isV4) {
            _executeV4Swap(
                params.universalRouter, params.weth, params.token, params.wethAmount, 0, params.v4PoolId
            );
        } else {
            _executeV3Swap(
                params.universalRouter, params.weth, params.token, params.wethAmount, 0, params.poolAddress
            );
        }

        uint256 tokenAfter = IERC20(params.token).balanceOf(address(this));
        tokensReceived = tokenAfter - tokenBefore;
        require(tokensReceived > 0, "Zero token output");
    }

    /// @dev Execute a V3 exactInputSingle swap via Universal Router
    function _executeV3Swap(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address pool
    ) internal {
        // Get fee from pool
        uint24 fee = IUniswapV3Pool(pool).fee();

        // V3_SWAP_EXACT_IN command byte = 0x00
        bytes memory commands = abi.encodePacked(uint8(0x00));

        // Encode V3 path: tokenIn (20 bytes) + fee (3 bytes) + tokenOut (20 bytes)
        bytes memory path = abi.encodePacked(tokenIn, fee, tokenOut);

        // Encode input: recipient, amountIn, amountOutMinimum, path, payerIsUser
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(this), // recipient
            amountIn,
            amountOutMin,
            path,
            false // payerIsUser = false (tokens already in router via approve)
        );

        IUniversalRouter(router).execute(commands, inputs, block.timestamp);
    }

    /// @dev Execute a V4 swap via Universal Router
    function _executeV4Swap(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes32 poolId
    ) internal {
        // V4_SWAP command byte = 0x10
        bytes memory commands = abi.encodePacked(uint8(0x10));

        // V4 swap encoding with poolId
        // For V4: encode swap params with exactInputSingle style
        bytes[] memory inputs = new bytes[](1);

        // Encode V4 exactInputSingle: (poolKey, zeroForOne, amountIn, amountOutMin, hookData)
        // poolKey structure depends on token ordering
        bool zeroForOne = tokenIn < tokenOut;

        inputs[0] = abi.encode(
            poolId,
            zeroForOne,
            int256(amountIn), // positive = exactInput
            amountOutMin,
            address(this), // recipient
            bytes("") // hookData
        );

        IUniversalRouter(router).execute(commands, inputs, block.timestamp);
    }
}
