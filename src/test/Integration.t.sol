// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/test/Utils.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {FixedRateFactory} from "src/FixedRateFactory.sol";
import {FixedRateStrategy} from "src/FixedRateStrategy.sol";
import {MockStrategy, Strategy} from "src/test/mocks/MockStrategy.sol";

interface IConvexStrategy {
    function strategist() external view returns (address);

    function withdrawalFee() external view returns (uint256);

    function FEE_DENOMINATOR() external view returns (uint256);

    function harvest(
        uint256 maxSlippageCRV,
        uint256 maxSlippageCVX,
        uint256 maxSlippageCRVAddLiquidity,
        uint256 maxSlippageEURS
    ) external;
}

interface IYVault {
    function earn() external;
}

contract IntegrationTest is UtilsTest {
    using FixedPointMathLib for uint256;

    FixedRateStrategy strategyFixedRate;

    ERC20 underlying;
    Strategy strategy;
    IConvexStrategy cvxStrategy;

    address public constant crveur = 0x194eBd173F6cDacE046C53eACcE9B953F28411d1;
    address public constant sdeursCRV = 0xCD6997334867728ba14d7922f72c893fcee70e84;
    address public constant strategyEurConvex = 0x6e6395cbF07Fe480dEae1076AA7d8A2B65edfC3d;

    function setUp() public {
        underlying = ERC20(crveur);
        strategy = Strategy(sdeursCRV);
        cvxStrategy = IConvexStrategy(strategyEurConvex);

        strategyFixedRate = new FixedRateFactory(user, Authority(address(0))).deployStrategy(underlying, strategy);
        strategyFixedRate.initialize();
        strategyFixedRate.setWithdrawalDelayPeriod(0);
    }

    function testHealthCheck() public {
        assertTrue(true);
    }

    function testFailHealCheck() public {
        assertFalse(true);
    }

    function testIntegration() public {
        deal(address(underlying), user, 1e18);
        underlying.approve(address(strategyFixedRate), 1e18);

        uint256 before = underlying.balanceOf(user);
        uint256 oldStrategyBalance = strategy.balance();

        strategyFixedRate.deposit(1e18);

        // In order to deactivate the fixed rate features, must set a big number.
        // If the expected profit are greater than the actual profits, then no protocol fees.
        strategyFixedRate.setFixedRate(1e18);

        assertEq(strategyFixedRate.totalHoldings(), 1e18);
        assertEq(strategyFixedRate.convertToUnderlying(1e18), 1e18);
        assertEq(strategyFixedRate.totalStrategyHoldings(), 1e18);
        assertEq(strategyFixedRate.balanceOf(user), 1e18);

        assertEq(strategy.balance(), oldStrategyBalance + 1e18);
        assertEq(underlying.balanceOf(user), before - 1e18);

        // ---  StakeDAO Mainnet flow.
        // Transfer to controller -> strategy
        IYVault(address(strategy)).earn();
        // Impersonate the strategist for harvest.
        address strategist = cvxStrategy.strategist();
        hoax(strategist);
        cvxStrategy.harvest(100, 100, 100, 100);
        // ---

        // Sync the fixed rate strategy with the underlying balance
        hevm.warp(block.timestamp + strategyFixedRate.harvestDelay());
        strategyFixedRate.harvest();

        uint256 balance = strategyFixedRate.balanceOfUnderlying(user);

        // Must have earned something, hopefully.
        assertGt(balance, before);

        // Withdraw the balance owed after harvest
        strategyFixedRate.withdraw(balance);

        assertEq(strategyFixedRate.totalHoldings(), 0);
        assertEq(strategyFixedRate.totalStrategyHoldings(), 0);
        assertEq(strategyFixedRate.balanceOf(user), 0);
        assertEq(strategyFixedRate.totalSupply(), 0);

        // Balance should be near the owed balance minus cvx strategy withdrawal fees.
        uint256 delta = balance.mulDivDown(cvxStrategy.withdrawalFee(), cvxStrategy.FEE_DENOMINATOR());
        assertApproxEq(underlying.balanceOf(user), balance, delta);
    }

    function testIntegrationWithFixedRate() public {
        // Equivalent to 1% APY
        // Mainnet EUR Strategy is around 3%
        uint256 rate = 317097919;
        strategyFixedRate.setFixedRate(rate);

        vm.startPrank(user1);

        deal(address(underlying), user1, 1e18);
        underlying.approve(address(strategyFixedRate), 1e18);


        uint256 before = underlying.balanceOf(user1);
        uint256 oldStrategyBalance = strategy.balance();

        strategyFixedRate.deposit(1e18);

        assertEq(strategyFixedRate.totalHoldings(), 1e18);
        assertEq(strategyFixedRate.convertToUnderlying(1e18), 1e18);
        assertEq(strategyFixedRate.totalStrategyHoldings(), 1e18);
        assertEq(strategyFixedRate.balanceOf(user1), 1e18);

        assertEq(strategy.balance(), oldStrategyBalance + 1e18);
        assertEq(underlying.balanceOf(user1), before - 1e18);

        vm.stopPrank();

        // ---  StakeDAO Mainnet flow.
        // Transfer to controller -> strategy
        IYVault(address(strategy)).earn();
        // Impersonate the strategist for harvest.
        address strategist = cvxStrategy.strategist();
        hoax(strategist);
        cvxStrategy.harvest(100, 100, 100, 100);
        // ---

        // ADMIN/KEEPER
        // Sync the fixed rate strategy with the underlying balance
        hevm.warp(block.timestamp + strategyFixedRate.harvestDelay());
        strategyFixedRate.harvest();
        hevm.warp(block.timestamp + strategyFixedRate.harvestDelay());

        uint256 strategyBalance = strategyFixedRate.getStrategyBalanceOfUnderlying();

        vm.startPrank(user1);
        uint256 balance = strategyFixedRate.balanceOfUnderlying(user1);

        // Must have earned something, hopefully.
        // balance > before
        assertGt(balance, before);

        uint256 delta = balance.mulDivDown(1, 1000); // 0.1% margin error
        // Earnings With a 1% Fixed Rate in 24 hours.
        assertApproxEq(balance, 10000273927e8, delta); 

        // Withdraw the balance owed after harvest
        strategyFixedRate.withdraw(balance);

        // Balance should be near the owed balance minus cvx strategy withdrawal fees.
        delta = balance.mulDivDown(cvxStrategy.withdrawalFee(), cvxStrategy.FEE_DENOMINATOR());
        assertApproxEq(underlying.balanceOf(user1), balance, delta);
        vm.stopPrank();

        // ADMIN/KEEPER
        // Claim profit
        strategyFixedRate.claimProfit();

        uint expectedProfit = strategyBalance - balance;
        delta = expectedProfit.mulDivDown(cvxStrategy.withdrawalFee(), cvxStrategy.FEE_DENOMINATOR()) + 1;
        assertApproxEq(underlying.balanceOf(user), expectedProfit, delta);
    }
}
