// spdx-license-identifier: agpl-3.0-only
pragma solidity 0.8.10;

import "src/interfaces/IStrategy.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract MockStrategy is Strategy {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    ERC20 public immutable token;

    constructor(ERC20 _underlying)
        ERC20(
            string(abi.encodePacked("Mocked Strategy ", _underlying.name())),
            string(abi.encodePacked("ms", _underlying.symbol())),
            _underlying.decimals()
        )
    {
        token = _underlying;
    }

    function deposit(uint256 _amount) public override {
        uint256 _pool = balance();
        uint256 _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = token.balanceOf(address(this));

        _amount = _after - _before; // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply) / _pool;
        }
        _mint(msg.sender, shares);
    }

    function depositAll() public override {
        deposit(token.balanceOf(msg.sender));
    }

    function withdraw(uint256 _shares) public override {
        uint256 r = (balance() * _shares) / totalSupply;
        _burn(msg.sender, _shares);

        // Check balance
        uint256 b = token.balanceOf(address(this));

        if (b < r) {
            uint256 _withdraw = r - b;
            uint256 _after = token.balanceOf(address(this));
            uint256 _diff = _after - b;
            if (_diff < _withdraw) {
                r = b + _diff;
            }
        }
        token.safeTransfer(msg.sender, r);
    }

    function balance() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    function withdrawAll() external override {
        withdraw(balanceOf[msg.sender]);
    }

    function getPricePerFullShare() public view override returns (uint256) {
        return (balance() * 1e18) / totalSupply;
    }
}
