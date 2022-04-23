// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth} from "solmate/auth/Auth.sol";
import {Strategy, ERC20} from "src/interfaces/IStrategy.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @title FixedRateStrategy
/// @author Warren
contract FixedRateStrategy is Auth, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ////////////////////////////////////////////////////////////////
    /// --- IMMUTABLES
    ///////////////////////////////////////////////////////////////

    /// @notice The underlying token the strategy accepts.
    ERC20 public immutable underlying;

    /// @notice The strategy where underlying is deposited on.
    Strategy public immutable strategy;

    /// @notice Total underlying amount lent to strategy.
    uint256 public totalStrategyHoldings;

    /// @notice Total shares.
    uint256 public totalSupply;

    ////////////////////////////////////////////////////////////////
    /// --- ACCOUNT STORAGE
    ///////////////////////////////////////////////////////////////

    /// @notice Accounting of user balance.
    mapping(address => uint256) private balances;

    /// @notice Deposit Timestamp
    /// @dev Timer resets every new deposit.
    mapping(address => uint256) public depositTimestamp;

    ////////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @notice Creates a new fixed rate strategy that accepts a specific underlying token.
    /// @param _underlying The ERC20 compliant token the strategy should accept.
    /// @param _strategy The Strategy underlying is deposited on.
    constructor(ERC20 _underlying, Strategy _strategy) Auth(Auth(msg.sender).owner(), Auth(msg.sender).authority()) {
        strategy = _strategy;
        underlying = _underlying;

        // Prevent deposit until the initialize function is called.
        totalSupply = type(uint256).max;
    }

    ////////////////////////////////////////////////////////////////
    /// --- ACCOUNTING VIEWS
    ///////////////////////////////////////////////////////////////

    function totalFloat() public view returns (uint256 totalFloatHeld) {
        totalFloatHeld = underlying.balanceOf(address(this));
    }

    function totalHoldings() public view returns (uint256 totalUnderlyingManaged) {
        totalUnderlyingManaged = totalFloat() + totalStrategyHoldings;
    }

    function balanceOf(address who) public view returns (uint256) {
        return balances[who];
    }

    function convertToShares(uint256 underlyingAmount) public view returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? underlyingAmount : underlyingAmount.mulDivDown(supply, totalHoldings());
    }

    function convertToUnderlying(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? shares : shares.mulDivDown(totalHoldings(), supply);
    }

    function getStrategyBalanceOfUnderlying() public view returns (uint256 totalStrategyBalance) {
        totalStrategyBalance = strategy.balanceOf(address(this)).mulWadUp(strategy.getPricePerFullShare());
    }

    function balanceOfUnderlying(address who) public view returns (uint256) {
        return convertToUnderlying(balances[who]);
    }

    ////////////////////////////////////////////////////////////////
    /// --- DEPOSIT LOGIC
    ///////////////////////////////////////////////////////////////

    function previewDeposit(uint256 underlyingAmount) public view returns (uint256) {
        return convertToShares(underlyingAmount);
    }

    function deposit(uint256 underlyingAmount) public nonReentrant returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(underlyingAmount)) != 0, "ZERO_SHARES");

        underlying.safeTransferFrom(msg.sender, address(this), underlyingAmount);

        // Update total supply and caller data.
        totalSupply = totalSupply + shares;
        balances[msg.sender] = balances[msg.sender] + shares;
        depositTimestamp[msg.sender] = block.timestamp;

        depositIntoStrategy(underlyingAmount);
    }

    function depositIntoStrategy(uint256 underlyingAmount) internal {
        totalStrategyHoldings += underlyingAmount;

        underlying.safeApprove(address(strategy), underlyingAmount);

        strategy.deposit(underlyingAmount);
    }

    ////////////////////////////////////////////////////////////////
    /// --- WITHDRAWAL LOGIC
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted after a successful harvest.
    event WithdrawalDelayUpdated(address indexed user, uint256 newPeriod);

    /// @notice The period in seconds over which withdrawal isn't permitted.
    uint64 public withdrawalDelayPeriod = 91 days;

    /// @notice Update the fixed rate.
    /// @dev Per second. Example: APR / 365 / 86_400
    function setWithdrawalDelayPeriod(uint64 newPeriod) external requiresAuth {
        withdrawalDelayPeriod = newPeriod;
        emit WithdrawalDelayUpdated(msg.sender, newPeriod);
    }

    function previewWithdraw(uint256 underlyingAmount) public view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? underlyingAmount : underlyingAmount.mulDivUp(supply, totalHoldings());
    }

    function withdraw(uint256 underlyingAmount) public nonReentrant returns (uint256 shares) {
        require(underlyingAmount > 0, "UNDERLYING_AMOUNT_ZERO");
        require(depositTimestamp[msg.sender] + withdrawalDelayPeriod <= block.timestamp, "WITHDRAWAL_TOO_SOON");

        shares = previewWithdraw(underlyingAmount);

        // Update total supply and caller data.
        totalSupply = totalSupply - shares;
        balances[msg.sender] = balances[msg.sender] - shares;

        // If total float balance is insufficient, withdraw from strategy.
        underlyingAmount = retrieveUnderlying(underlyingAmount);

        // Transfer to caller.
        underlying.safeTransfer(msg.sender, underlyingAmount);
    }

    function withdrawFromStrategy(uint256 underlyingAmount) internal {
        uint256 shares = underlyingAmount.mulDivDown(strategy.totalSupply(), strategy.balance());

        totalStrategyHoldings = totalStrategyHoldings - underlyingAmount;

        strategy.withdraw(shares);
    }

    function retrieveUnderlying(uint256 underlyingAmount) internal returns (uint256) {
        uint256 float = totalFloat();

        if (underlyingAmount > float) {
            withdrawFromStrategy(underlyingAmount - float);
            return totalFloat();
        }

        return underlyingAmount;
    }

    ////////////////////////////////////////////////////////////////
    /// --- HARVEST LOGIC
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted after a successful harvest.
    event Harvest(address indexed user);

    /// @notice Emitted when the harvest delay is updated.
    /// @param newHarvestDelay The new harvest delay.
    event HarvestDelayUpdated(address indexed user, uint64 newHarvestDelay);

    /// @notice Emitted when the protocol profits are claimed.
    event FixRateUpdated(address indexed user, uint256 newRate);

    /// @notice A fixed rate per second.
    uint256 public fixedRatePerSecond;

    /// @notice Update the fixed rate.
    /// @dev Per second. Example: APR / 365 / 86_400
    function setFixedRate(uint256 rate) external requiresAuth {
        fixedRatePerSecond = rate;
        emit FixRateUpdated(msg.sender, rate);
    }

    /// @notice Sets a new harvest delay.
    function setHarvestDelay(uint64 newHarvestDelay) external requiresAuth {
        // A harvest delay of 0 makes harvests vulnerable to sandwich attacks.
        require(newHarvestDelay != 0, "DELAY_CANNOT_BE_ZERO");
        require(newHarvestDelay <= 365 days, "DELAY_TOO_LONG");

        // If the harvest delay is 0, meaning it has not been set before:
        if (harvestDelay == 0) {
            // We'll apply the update immediately.
            harvestDelay = newHarvestDelay;

            emit HarvestDelayUpdated(msg.sender, newHarvestDelay);
        } else {
            // We'll apply the update next harvest.
            nextHarvestDelay = newHarvestDelay;
        }
    }

    /// @notice A timestamp representing when the most recent harvest occurred.
    uint64 public lastHarvest;

    /// @notice The period in seconds over which locked profit is unlocked.
    /// @dev Cannot be 0 as it opens harvests up to sandwich attacks.
    uint64 public harvestDelay = 1 days;

    /// @notice The next period to replace harvestDelay next harvest.
    /// @dev If 0, no update.
    uint64 public nextHarvestDelay;

    /// @notice Harvest profits from passive strategies.
    function harvest() public nonReentrant requiresAuth {
        require(block.timestamp >= lastHarvest + harvestDelay, "BAD_HARVEST_TIME");

        // Compute the time elapsed between the last harvest and now.
        uint256 timeElapsed = block.timestamp - lastHarvest;

        // Cache the total profit accrued by the strategy
        // Current balance of the strategy minus the balance of strategy before harvest.
        uint256 totalProfitAccrued = getStrategyBalanceOfUnderlying() - totalStrategyHoldings;

        // Compute the minimum expected profit based from the fixed rate.
        uint256 totalProfitExpectedRate = totalStrategyHoldings.mulWadDown(fixedRatePerSecond * timeElapsed);

        // Delta = Real Profit - Expected Profit.
        // If positive, delta represent protocol profits.
        uint256 delta;

        unchecked {
            // Can't underflow.
            delta = totalProfitAccrued > totalProfitExpectedRate ? totalProfitAccrued - totalProfitExpectedRate : 0;
        }

        if (delta > 0) {
            // Compute the amount of shares to attribute as profits.
            uint256 shares = previewDeposit(delta);

            // Update total supply and balance accordingly.
            totalSupply += shares;
            balances[address(this)] += shares;
        }

        // Update the strategy holdings with the update balance.
        totalStrategyHoldings = getStrategyBalanceOfUnderlying();

        // Update the last harvest timestamp.
        lastHarvest = uint64(block.timestamp);

        emit Harvest(msg.sender);

        // Get the next harvest delay.
        uint64 newHarvestDelay = nextHarvestDelay;

        // If the next harvest delay is not 0:
        if (newHarvestDelay != 0) {
            // Update the harvest delay.
            harvestDelay = newHarvestDelay;

            // Reset the next harvest delay.
            nextHarvestDelay = 0;

            emit HarvestDelayUpdated(msg.sender, newHarvestDelay);
        }
    }

    ////////////////////////////////////////////////////////////////
    /// --- FEE CLAIM LOGIC
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when the protocol profits are claimed.
    event ProfitClaimed(address indexed user, uint256 underlyingAmount);

    /// @notice Claims profit accrued from harvests.
    function claimProfit() external requiresAuth returns (uint256 underlyingAmount) {
        emit ProfitClaimed(msg.sender, balances[address(this)]);

        underlyingAmount = convertToUnderlying(balances[address(this)]);

        totalSupply -= balances[address(this)];
        balances[address(this)] = 0;

        underlyingAmount = retrieveUnderlying(underlyingAmount);

        // Transfer the provided amount of underlyingAmount to the caller.
        ERC20(underlying).safeTransfer(msg.sender, underlyingAmount);
    }

    ////////////////////////////////////////////////////////////////
    /// --- INITIALIZATION LOGIC
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when the Strategy is initialized.
    event Initialized(address indexed user);

    /// @notice Whether the Strategy has been initialized yet.
    bool public isInitialized;

    /// @notice Initializes the Strategy, enabling it to receive deposits.
    /// @dev All parameters must already be set before calling such as:
    ///  Fixed Rate, Harvest Delay,
    function initialize() external requiresAuth {
        // Ensure the Strategy has not already been initialized.
        require(!isInitialized, "ALREADY_INITIALIZED");

        // Mark the Strategy as initialized.
        isInitialized = true;

        lastHarvest = uint64(block.timestamp);

        // Open for deposits.
        totalSupply = 0;

        emit Initialized(msg.sender);
    }
}
