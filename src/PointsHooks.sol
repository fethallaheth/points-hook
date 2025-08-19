// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

/**
 * @dev This contract is responsible for minting points to users based on their Ethereum swaps.
 * @author ChaosSR
 * @notice This is not for production 
 */
contract PointsHooks is BaseHook, ERC1155 {
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // DOC : the msg.sender here isn't actually the EOA
    // EOA -> ROUTER -> UNISWAP -> Hook (multiple calls)
    // msg.sender is the Uniswap contract address
    // tx.origin is the EOA address but @note its not recommended to use tx.origin
    // @audit when user withdraw the amount (swap Tokens for ETH) he still have the ERC1155 balance 
    // should burn it when we withdraw( swaps against)
    // transfer it when you transfer the token  
    function _afterSwap(
        address,
        PoolKey calldata _poolKey,
        SwapParams calldata _swapParams,
        BalanceDelta _delta,
        bytes calldata _hookData
    ) internal override returns (bytes4, int128) {
        // make sure this an Eth <> token pool
        if (!_poolKey.currency0.isAddressZero()) {
            return (this.afterSwap.selector, 0);
        }

        // make sure the swap is to buy token
        // if the swap is zeroForOne, it means we are swapping token0 for token1
        // we know that Eth is always token0
        if (!_swapParams.zeroForOne) {
            return (this.afterSwap.selector, 0);
        }

        // mint points equal 20% of the amount of Eth being swapped
        // The desired input amount if negative (exactIn), or the desired output amount if positive (exactOut)
        // if amountSpecified < 0 : 'exactnput for output' : amount of ETH they spent is equal to 'amountSpecified'
        // if amountSpecified > 0 : 'exactoutput for input' : amount of ETH they received is equal to 'amountSpecified'
        uint256 ethSpendAmount = uint256(int256(-_delta.amount0()));
        // @audit precesion loss when dividing by 5; 
        // use fractional div :: user loss as it round down  
        // EX::  49 / 5 = 9
        uint256 pointsForSwap = ethSpendAmount / 5;

        // @note add check to see if the pointsForSwap is greater than 0
        _assignPoints(_poolKey.toId(), _hookData, pointsForSwap);

        // Return our selector
        return (this.afterSwap.selector, 0);
    }
    // @audit low use uint256 instead of uint 
    function _assignPoints(
        PoolId _poolId, 
        bytes calldata _hookData, 
        uint256 _points
    ) internal {
        // wnsure we pass hookdata , if missed no points
        if (_hookData.length == 0) { return; }

        // extract a user address from the hook data
        address user = abi.decode(_hookData, (address));

        // if the user address is decoded as a zero address, no points
        if (user == address(0)) { return; }

        // mint points to the user
        uint256 poolIdUint = uint256(PoolId.unwrap(_poolId));
        _mint(user, poolIdUint, _points, "");
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "https://example.com/metadata/{id}.json";
    }
}
