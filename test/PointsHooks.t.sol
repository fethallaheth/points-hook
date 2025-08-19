// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {PointsHooks} from "../src/PointsHooks.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

contract TestPointsHook is Test, Deployers, ERC1155TokenReceiver {
    
    MockERC20 token;    
    

    PointsHooks public pointsHook;
    
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;
    

    function setUp() public {

        // Deploy the Uniswap V4 PoolManager
        deployFreshManagerAndRouters();

        // deploy the ERC20 token
        token = new MockERC20("TOKEN", "TKN", 18);
        tokenCurrency = Currency.wrap(address(token));
        
        // Mint some tokens to the contract and address(1)
        token.mint(address(this), 1000 ether);
        token.mint(address(1), 1000 ether);
        
        // Deploy the Hook to an address that has the proper flags set 
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("PointsHooks.sol", abi.encode(manager), address(flags));
        
        // Deploy our hook 
        pointsHook = PointsHooks(address(flags));

        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Initialize the pool
        (key ,) = initPool(
                ethCurrency, 
                tokenCurrency, 
                pointsHook, 
                3000, 
                SQRT_PRICE_1_1
            );


        // Add some liquidity to the pool
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 0.1 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            SQRT_PRICE_1_1, 
            sqrtPriceAtTickUpper, 
            ethToAdd
        );

        uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtPriceAtTickLower, 
            SQRT_PRICE_1_1,
            liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        // add liquidity to the pool
    }

    function test_swap() public {
       uint256 pooldUint = uint256(PoolId.unwrap(key.toId()));
       uint256 pointsBalanceOriginal = pointsHook.balanceOf(address(this), pooldUint); 
       
       
        bytes memory hookData = abi.encode(address(this));
        // call the swap router to make a 0.001 ETH swap
        swapRouter.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings(false, false),
            hookData
        );
        
        uint256 pointsBalanceAfter = pointsHook.balanceOf(address(this), pooldUint);

        // Checkmy points balance after the swap
        assertEq(pointsBalanceAfter - pointsBalanceOriginal, 2 * 10 ** 14, "Points balance should be increased by 2000");
    }
}
