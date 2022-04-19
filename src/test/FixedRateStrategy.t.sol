// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/test/Utils.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {FixedRateFactory} from "src/FixedRateFactory.sol";
import {FixedRateStrategy} from "src/FixedRateStrategy.sol";
import {MockStrategy} from "src/test/mocks/MockStrategy.sol";

contract FixedRateStrategyTest is UtilsTest {
    using FixedPointMathLib for uint256;

    FixedRateStrategy strategyFixedRate;

    MockERC20 underlying;
    MockStrategy strategy;

    function setUp() public {
        underlying = new MockERC20("Token", "TKO", 18);
        strategy = new MockStrategy(underlying);

        strategyFixedRate = new FixedRateFactory(user, Authority(address(0))).deployStrategy(underlying, strategy);
        strategyFixedRate.initialize();
    }

    function testHealthCheck() public {
        assertTrue(true);
    }

    function testFailHealCheck() public {
        assertFalse(true);
    }

    function testDeposit() public {
        underlying.mint(user, 100e18);
        underlying.approve(address(strategyFixedRate), 100e18);
        uint256 before = underlying.balanceOf(user);
        strategyFixedRate.deposit(100e18);

        assertEq(strategyFixedRate.totalHoldings(), 100e18);
        assertEq(strategyFixedRate.convertToUnderlying(100e18), 100e18);
        assertEq(strategyFixedRate.totalStrategyHoldings(), 100e18);
        assertEq(strategyFixedRate.balanceOf(user), 100e18);

        assertEq(strategy.balance(), 100e18);
        assertEq(underlying.balanceOf(user), before - 100e18);
    }

    function testWithdraw() public {
        underlying.mint(user, 100e18);
        underlying.approve(address(strategyFixedRate), 100e18);

        uint256 before = underlying.balanceOf(user);
        strategyFixedRate.deposit(100e18);

        assertEq(underlying.balanceOf(user), before - 100e18);

        hevm.expectRevert("WITHDRAWAL_TOO_SOON");
        strategyFixedRate.withdraw(100e18);

        hevm.warp(block.timestamp + strategyFixedRate.withdrawalDelayPeriod());

        strategyFixedRate.withdraw(100e18);

        assertEq(strategyFixedRate.totalHoldings(), 0);
        assertEq(strategyFixedRate.convertToUnderlying(100e18), 100e18);
        assertEq(strategyFixedRate.totalStrategyHoldings(), 0);
        assertEq(strategyFixedRate.balanceOf(user), 0);
        assertEq(strategyFixedRate.totalSupply(), 0);

        assertEq(strategy.balance(), 0);
        assertEq(underlying.balanceOf(user), before);
    }

    function testProfitableFixedRateHarvest() public {
        underlying.mint(user, 100e18);
        underlying.approve(address(strategyFixedRate), 100e18);

        underlying.mint(address(strategy), 100e18);

        strategyFixedRate.deposit(100e18);
        strategyFixedRate.setFixedRate(317097919838);

        assertEq(strategy.balance(), 200e18);
        assertEq(underlying.balanceOf(user), 0);
        hevm.warp(block.timestamp + strategyFixedRate.harvestDelay());

        uint256 elapsedTime = block.timestamp - strategyFixedRate.lastHarvest();

        uint256 profit = strategyFixedRate.getStrategyBalanceOfUnderlying() - strategyFixedRate.totalStrategyHoldings();
        uint256 expectedProfit = strategyFixedRate.totalHoldings().mulWadDown((317097919838 * elapsedTime));
        uint256 expectedFees = strategyFixedRate.convertToShares(profit - expectedProfit);

        strategyFixedRate.harvest();

        assertEq(strategyFixedRate.balanceOf(address(strategyFixedRate)), expectedFees);

        hevm.warp(block.timestamp + strategyFixedRate.withdrawalDelayPeriod());
        strategyFixedRate.withdraw(strategyFixedRate.balanceOfUnderlying(user));
    }

    function testUnProfitableFixedRateHarvest() public {
        underlying.mint(user, 100e18);
        underlying.approve(address(strategyFixedRate), 100e18);

        underlying.mint(address(strategy), 100e18);

        strategyFixedRate.deposit(100e18);
        strategyFixedRate.setFixedRate(1e18); // Fixed Rate is higher than what the strategy earns.

        hevm.warp(block.timestamp + strategyFixedRate.harvestDelay());

        strategyFixedRate.harvest();

        assertEq(strategyFixedRate.balanceOf(address(strategyFixedRate)), 0); // No profit made
    }

    function testClaimProfit() public {
        underlying.mint(user, 100e18);
        underlying.approve(address(strategyFixedRate), 100e18);

        underlying.mint(address(strategy), 100e18);

        strategyFixedRate.deposit(100e18);
        strategyFixedRate.setFixedRate(317097919838);

        hevm.warp(block.timestamp + strategyFixedRate.harvestDelay());

        strategyFixedRate.harvest();

        uint256 expectedFees = strategyFixedRate.convertToUnderlying(
            strategyFixedRate.balanceOf(address(strategyFixedRate))
        );

        assertEq(underlying.balanceOf(user), 0);

        strategyFixedRate.claimProfit();
        assertEq(underlying.balanceOf(user), expectedFees);

        hevm.warp(block.timestamp + strategyFixedRate.withdrawalDelayPeriod());
        strategyFixedRate.withdraw(strategyFixedRate.balanceOfUnderlying(user));
    }
}
