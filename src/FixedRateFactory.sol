// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

import {Strategy} from "src/interfaces/IStrategy.sol";
import {FixedRateStrategy} from "src/FixedRateStrategy.sol";

contract FixedRateFactory is Auth {
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;

    /// @notice Creates a FixedRateStrategy factory.
    /// @param _owner The owner of the factory.
    /// @param _authority The Authority of the factory.
    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    ////////////////////////////////////////////////////////////////
    /// --- STRATEGY DEPLOYMENT LOGIC
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when a new FixedRateStrategy is deployed.
    /// @param strategy The newly deployed FixedRateStrategy contract.
    /// @param underlying The underlying token the new FixedRateStrategy accepts.
    event StrategyDeployed(FixedRateStrategy strategy, ERC20 underlying);

    /// @notice Deploys a new FixedRateStrategy which supports a specific underlying token.
    /// @param underlying The ERC20 token that the FixedRateStrategy should accept.
    /// @param strategy The Strategy that the FixedRateStrategy should deposit to.
    /// @return strategy The newly deployed FixedRateStrategy contract which accepts the provided underlying token.
    function deployStrategy(ERC20 underlying, Strategy _strategy)
        external
        requiresAuth
        returns (FixedRateStrategy strategy)
    {
        // This will revert if a FixedRateStrategy which accepts this _strategy has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        strategy = new FixedRateStrategy{salt: address(_strategy).fillLast12Bytes()}(underlying, _strategy);

        emit StrategyDeployed(strategy, underlying);
    }

    ////////////////////////////////////////////////////////////////
    /// --- STRATEGY LOOKUP
    ///////////////////////////////////////////////////////////////

    function getStrategyFromUnderlyingAndStrategy(ERC20 underlying, Strategy strategy)
        external
        view
        returns (FixedRateStrategy)
    {
        return
            FixedRateStrategy(
                payable(
                    keccak256(
                        abi.encodePacked(
                            // Prefix:
                            bytes1(0xFF),
                            // Creator:
                            address(this),
                            // Salt:
                            address(strategy).fillLast12Bytes(),
                            // Bytecode hash:
                            keccak256(
                                abi.encodePacked(
                                    // Deployment bytecode:
                                    type(FixedRateStrategy).creationCode,
                                    // Constructor arguments:
                                    abi.encode(underlying, strategy)
                                )
                            )
                        )
                    ).fromLast20Bytes() // Convert the CREATE2 hash into an address.
                )
            );
    }

    /// @notice Returns if a FixedRateStrategy at an address has already been deployed.
    /// @param strategy The address of a FixedRateStrategy which may not have been deployed yet.
    /// @return A boolean indicating whether the FixedRateStrategy has been deployed already.
    /// @dev This function is useful to check the return values of getVaultFromUnderlying,
    /// as it does not check that the FixedRateStrategy addresses it computes have been deployed yet.
    function isStrategyDeployed(FixedRateStrategy strategy) external view returns (bool) {
        return address(strategy).code.length > 0;
    }
}
