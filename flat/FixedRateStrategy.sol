// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

/// @notice Provides a flexible and updatable auth pattern which is completely separate from application logic.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/auth/Auth.sol)
/// @author Modified from Dappsys (https://github.com/dapphub/ds-auth/blob/master/src/auth.sol)
abstract contract Auth {
    event OwnerUpdated(address indexed user, address indexed newOwner);

    event AuthorityUpdated(address indexed user, Authority indexed newAuthority);

    address public owner;

    Authority public authority;

    constructor(address _owner, Authority _authority) {
        owner = _owner;
        authority = _authority;

        emit OwnerUpdated(msg.sender, _owner);
        emit AuthorityUpdated(msg.sender, _authority);
    }

    modifier requiresAuth() {
        require(isAuthorized(msg.sender, msg.sig), "UNAUTHORIZED");

        _;
    }

    function isAuthorized(address user, bytes4 functionSig) internal view virtual returns (bool) {
        Authority auth = authority; // Memoizing authority saves us a warm SLOAD, around 100 gas.

        // Checking if the caller is the owner only after calling the authority saves gas in most cases, but be
        // aware that this makes protected functions uncallable even to the owner if the authority is out of order.
        return (address(auth) != address(0) && auth.canCall(user, address(this), functionSig)) || user == owner;
    }

    function setAuthority(Authority newAuthority) public virtual {
        // We check if the caller is the owner first because we want to ensure they can
        // always swap out the authority even if it's reverting or using up a lot of gas.
        require(msg.sender == owner || authority.canCall(msg.sender, address(this), msg.sig));

        authority = newAuthority;

        emit AuthorityUpdated(msg.sender, newAuthority);
    }

    function setOwner(address newOwner) public virtual requiresAuth {
        owner = newOwner;

        emit OwnerUpdated(msg.sender, newOwner);
    }
}

/// @notice A generic interface for a contract which provides authorization data to an Auth instance.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/auth/Auth.sol)
/// @author Modified from Dappsys (https://github.com/dapphub/ds-auth/blob/master/src/auth.sol)
interface Authority {
    function canCall(
        address user,
        address target,
        bytes4 functionSig
    ) external view returns (bool);
}

// spdx-license-identifier: agpl-3.0-only

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract ERC20 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public immutable decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }
}

abstract contract Strategy is ERC20 {
    function deposit(uint256 underlyingAmount) external virtual;

    function balance() external view virtual returns (uint256);

    function depositAll() external virtual;

    function withdraw(uint256 shares) external virtual;

    function withdrawAll() external virtual;

    function getPricePerFullShare() external view virtual returns (uint256);
}

/// @notice Gas optimized reentrancy protection for smart contracts.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/ReentrancyGuard.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol)
abstract contract ReentrancyGuard {
    uint256 private locked = 1;

    modifier nonReentrant() {
        require(locked == 1, "REENTRANCY");

        locked = 2;

        _;

        locked = 1;
    }
}

/// @notice Safe ETH and ERC20 transfer library that gracefully handles missing return values.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/SafeTransferLib.sol)
/// @dev Use with caution! Some functions in this library knowingly create dirty bits at the destination of the free memory pointer.
/// @dev Note that none of the functions in this library check that a token has code at all! That responsibility is delegated to the caller.
library SafeTransferLib {
    event Debug(bool one, bool two, uint256 retsize);

    /*//////////////////////////////////////////////////////////////
                             ETH OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function safeTransferETH(address to, uint256 amount) internal {
        bool success;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
    }

    /*//////////////////////////////////////////////////////////////
                            ERC20 OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function safeTransferFrom(
        ERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        bool success;

        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(freeMemoryPointer, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(freeMemoryPointer, 4), from) // Append the "from" argument.
            mstore(add(freeMemoryPointer, 36), to) // Append the "to" argument.
            mstore(add(freeMemoryPointer, 68), amount) // Append the "amount" argument.

            success := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                // We use 100 because the length of our calldata totals up like so: 4 + 32 * 3.
                // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                // Counterintuitively, this call must be positioned second to the or() call in the
                // surrounding and() call or else returndatasize() will be zero during the computation.
                call(gas(), token, 0, freeMemoryPointer, 100, 0, 32)
            )
        }

        require(success, "TRANSFER_FROM_FAILED");
    }

    function safeTransfer(
        ERC20 token,
        address to,
        uint256 amount
    ) internal {
        bool success;

        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(freeMemoryPointer, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(freeMemoryPointer, 4), to) // Append the "to" argument.
            mstore(add(freeMemoryPointer, 36), amount) // Append the "amount" argument.

            success := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                // We use 68 because the length of our calldata totals up like so: 4 + 32 * 2.
                // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                // Counterintuitively, this call must be positioned second to the or() call in the
                // surrounding and() call or else returndatasize() will be zero during the computation.
                call(gas(), token, 0, freeMemoryPointer, 68, 0, 32)
            )
        }

        require(success, "TRANSFER_FAILED");
    }

    function safeApprove(
        ERC20 token,
        address to,
        uint256 amount
    ) internal {
        bool success;

        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(freeMemoryPointer, 0x095ea7b300000000000000000000000000000000000000000000000000000000)
            mstore(add(freeMemoryPointer, 4), to) // Append the "to" argument.
            mstore(add(freeMemoryPointer, 36), amount) // Append the "amount" argument.

            success := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                // We use 68 because the length of our calldata totals up like so: 4 + 32 * 2.
                // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                // Counterintuitively, this call must be positioned second to the or() call in the
                // surrounding and() call or else returndatasize() will be zero during the computation.
                call(gas(), token, 0, freeMemoryPointer, 68, 0, 32)
            )
        }

        require(success, "APPROVE_FAILED");
    }
}

/// @notice Arithmetic library with operations for fixed-point numbers.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
/// @author Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
library FixedPointMathLib {
    /*//////////////////////////////////////////////////////////////
                    SIMPLIFIED FIXED POINT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant WAD = 1e18; // The scalar of ETH and most ERC20s.

    function mulWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD); // Equivalent to (x * y) / WAD rounded down.
    }

    function mulWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD); // Equivalent to (x * y) / WAD rounded up.
    }

    function divWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y); // Equivalent to (x * WAD) / y rounded down.
    }

    function divWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y); // Equivalent to (x * WAD) / y rounded up.
    }

    /*//////////////////////////////////////////////////////////////
                    LOW LEVEL FIXED POINT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // Divide z by the denominator.
            z := div(z, denominator)
        }
    }

    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // First, divide z - 1 by the denominator and add 1.
            // We allow z - 1 to underflow if z is 0, because we multiply the
            // end result by 0 if z is zero, ensuring we return 0 if z is zero.
            z := mul(iszero(iszero(z)), add(div(sub(z, 1), denominator), 1))
        }
    }

    function rpow(
        uint256 x,
        uint256 n,
        uint256 scalar
    ) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 {
                    // 0 ** 0 = 1
                    z := scalar
                }
                default {
                    // 0 ** n = 0
                    z := 0
                }
            }
            default {
                switch mod(n, 2)
                case 0 {
                    // If n is even, store scalar in z for now.
                    z := scalar
                }
                default {
                    // If n is odd, store x in z for now.
                    z := x
                }

                // Shifting right by 1 is like dividing by 2.
                let half := shr(1, scalar)

                for {
                    // Shift n right by 1 before looping to halve it.
                    n := shr(1, n)
                } n {
                    // Shift n right by 1 each iteration to halve it.
                    n := shr(1, n)
                } {
                    // Revert immediately if x ** 2 would overflow.
                    // Equivalent to iszero(eq(div(xx, x), x)) here.
                    if shr(128, x) {
                        revert(0, 0)
                    }

                    // Store x squared.
                    let xx := mul(x, x)

                    // Round to the nearest number.
                    let xxRound := add(xx, half)

                    // Revert if xx + half overflowed.
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }

                    // Set x to scaled xxRound.
                    x := div(xxRound, scalar)

                    // If n is even:
                    if mod(n, 2) {
                        // Compute z * x.
                        let zx := mul(z, x)

                        // If z * x overflowed:
                        if iszero(eq(div(zx, x), z)) {
                            // Revert if x is non-zero.
                            if iszero(iszero(x)) {
                                revert(0, 0)
                            }
                        }

                        // Round to the nearest number.
                        let zxRound := add(zx, half)

                        // Revert if zx + half overflowed.
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }

                        // Return properly scaled zxRound.
                        z := div(zxRound, scalar)
                    }
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        GENERAL NUMBER UTILITIES
    //////////////////////////////////////////////////////////////*/

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        assembly {
            // Start off with z at 1.
            z := 1

            // Used below to help find a nearby power of 2.
            let y := x

            // Find the lowest power of 2 that is at least sqrt(x).
            if iszero(lt(y, 0x100000000000000000000000000000000)) {
                y := shr(128, y) // Like dividing by 2 ** 128.
                z := shl(64, z) // Like multiplying by 2 ** 64.
            }
            if iszero(lt(y, 0x10000000000000000)) {
                y := shr(64, y) // Like dividing by 2 ** 64.
                z := shl(32, z) // Like multiplying by 2 ** 32.
            }
            if iszero(lt(y, 0x100000000)) {
                y := shr(32, y) // Like dividing by 2 ** 32.
                z := shl(16, z) // Like multiplying by 2 ** 16.
            }
            if iszero(lt(y, 0x10000)) {
                y := shr(16, y) // Like dividing by 2 ** 16.
                z := shl(8, z) // Like multiplying by 2 ** 8.
            }
            if iszero(lt(y, 0x100)) {
                y := shr(8, y) // Like dividing by 2 ** 8.
                z := shl(4, z) // Like multiplying by 2 ** 4.
            }
            if iszero(lt(y, 0x10)) {
                y := shr(4, y) // Like dividing by 2 ** 4.
                z := shl(2, z) // Like multiplying by 2 ** 2.
            }
            if iszero(lt(y, 0x8)) {
                // Equivalent to 2 ** z.
                z := shl(1, z)
            }

            // Shifting right by 1 is like dividing by 2.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // Compute a rounded down version of z.
            let zRoundDown := div(x, z)

            // If zRoundDown is smaller, use it.
            if lt(zRoundDown, z) {
                z := zRoundDown
            }
        }
    }
}

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

        // Need to transfer before storage update  or ERC777s could reenter.
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

    function previewWithdraw(uint256 underlyingAmount) public view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? underlyingAmount : underlyingAmount.mulDivUp(supply, totalHoldings());
    }

    function withdraw(uint256 underlyingAmount) public nonReentrant returns (uint256 shares) {
        require(underlyingAmount > 0, "UNDERLYING_AMOUNT_ZERO");
        require(depositTimestamp[msg.sender] + withdrawalDelayPeriod <= block.timestamp, "WITHDRAWAL_TOO_SOON");

        // No need to check for rounding error, previewWithdraw rounds up.
        shares = previewWithdraw(underlyingAmount);

        // Update total supply and caller data.
        totalSupply = totalSupply - shares;
        balances[msg.sender] = balances[msg.sender] - shares;

        // If total float balance is unsuficient, withdraw from strategy.

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

        return float - underlyingAmount;
    }

    ////////////////////////////////////////////////////////////////
    /// --- HARVEST LOGIC
    ///////////////////////////////////////////////////////////////

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

    /// @notice A timestamp representing when the most recent harvest occurred.
    uint64 public lastHarvest;

    /// @notice The period in seconds over which withdrawal isn't permitted.
    uint64 public withdrawalDelayPeriod = 91 days;

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

        // Open for deposits.
        totalSupply = 0;

        emit Initialized(msg.sender);
    }
}

