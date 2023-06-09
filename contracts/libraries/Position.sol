// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './FullMath.sol';
import './FixedPoint128.sol';
import './LiquidityMath.sol';

/// @title Position
// 头寸表示所有者地址在上下刻度边界之间的流动性
/// @notice Positions represent an owner address' liquidity between a lower and upper tick boundary
// 头寸储存额外的状态,以追踪所欠职位的费用
/// @dev Positions store additional state for tracking fees owed to the position
library Position {
    // 存储每个用户头寸的信息
    // info stored for each user's position
    struct Info {
        // 头寸持有的流动资金
        // the amount of liquidity owned by this position
        uint128 liquidity;
        // 截至上次更新为流动性或所欠费用时，每单位流动性的费用增长
        // 此 position 内的手续费总额
        // fee growth per unit of liquidity as of the last update to liquidity or fees owed
        uint256 feeGrowthInside0LastX128;
        // 这个值不需要每次都更新，它只会在 position 发生变动，或者用户提取手续费时更新
        uint256 feeGrowthInside1LastX128;
        // 在token0/token1中应给予头寸所有者的费用
        // the fees owed to the position owner in token0/token1
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    // 返回给定所有者和位置边界的位置的Info结构
    /// @notice Returns the Info struct of a position, given an owner and position boundaries
    /// @param self The mapping containing all user positions
    /// @param owner The address of the position owner
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return position The position info struct of the given owners' position
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (Position.Info storage position) {
        // keccak256(abi.encodePacked(owner, tickLower, tickUpper)) 返回一个bytes32的字节数组
        position = self[keccak256(abi.encodePacked(owner, tickLower, tickUpper))];
    }

    // 积分累计到用户头寸的费用
    /// @notice Credits accumulated fees to a user's position
    /// @param self The individual position to update
    /// @param liquidityDelta The change in pool liquidity as a result of the position update
    /// @param feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
    /// @param feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick boundaries
    function update(
        Info storage self,//头寸详情
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        Info memory _self = self;

        // 之后要更新的流动性
        uint128 liquidityNext;
        if (liquidityDelta == 0) {
            // 没有流动性变化
            // 原本流动性必须大于0
            require(_self.liquidity > 0, 'NP'); // disallow pokes for 0 liquidity positions
            // 之后的流动性也还是00
            liquidityNext = _self.liquidity;
        } else {
            // 加上流动性变量（流动性变量liquidityDelta可能是负值）
            liquidityNext = LiquidityMath.addDelta(_self.liquidity, liquidityDelta);
        }

        // calculate accumulated fees
        // 计算累计费用
        uint128 tokensOwed0 = uint128(
            // 除FixedPoint128.Q128是转换成浮点数
            // 这次累计费用-上次累积费用=费用变量
            // 费用变量 * 流动性 = 应支付的token0费用
            FullMath.mulDiv(feeGrowthInside0X128 - _self.feeGrowthInside0LastX128, _self.liquidity, FixedPoint128.Q128)
        );
        uint128 tokensOwed1 = uint128(
            FullMath.mulDiv(feeGrowthInside1X128 - _self.feeGrowthInside1LastX128, _self.liquidity, FixedPoint128.Q128)
        );

        // update the position
        // 更新流动性
        if (liquidityDelta != 0) self.liquidity = liquidityNext;
        // 更新累计费用
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            // overflow is acceptable, have to withdraw before you hit type(uint128).max fees
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }
    }
}
