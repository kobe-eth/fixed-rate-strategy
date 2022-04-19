// spdx-license-identifier: agpl-3.0-only
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";

abstract contract Strategy is ERC20 {
    function deposit(uint256 underlyingAmount) external virtual;

    function balance() external view virtual returns (uint256);

    function depositAll() external virtual;

    function withdraw(uint256 shares) external virtual;

    function withdrawAll() external virtual;

    function getPricePerFullShare() external view virtual returns (uint256);
}
