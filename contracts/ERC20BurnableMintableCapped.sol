// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { ERC20 } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/test/ERC20.sol';
import { Ownable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/utils/Ownable.sol';
import { IERC20BurnableMintableCapped } from './interfaces/IERC20BurnableMintableCapped.sol';

contract ERC20BurnableMintableCapped is ERC20, Ownable, IERC20BurnableMintableCapped {
    uint256 public immutable cap;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 cap_, address owner) ERC20(name_, symbol_, decimals_) {
        cap = cap_;
        if (cap > 0) {
            _mint(owner, cap);
        }
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(_OWNER_SLOT, owner)
        }
    }

    function mint(address account, uint256 amount) external onlyOwner {
        uint256 capacity = cap;

        _mint(account, amount);

        if (capacity != 0 && totalSupply > capacity) revert CapExceeded();
    }

    function burnFrom(address account, uint256 amount) external onlyOwner {
        uint256 _allowance = allowance[account][msg.sender];
        if (_allowance != type(uint256).max) {
            _approve(account, msg.sender, _allowance - amount);
        }
        _burn(account, amount);
    }
}
