// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../GenericLender/GenericSilo.sol";

contract GenericSiloTest is GenericSilo {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // initialisation and constructor - passing staking contracts as argument 
    constructor(
        address _strategy,
        string memory name,
        address _xaivault
    ) public GenericSilo(_strategy, name, _xaivault) {
        
    }

    function test_rebalance() external {
        _rebalance();
    }

    function test_depositToSilo() external {
        _depositToSilo();
    }
    function test_withdrawFromSilo(uint256 _amount) external {
        _withdrawFromSilo(_amount);
    }
    function test_borrowFromSilo(uint256 _xaiAmount) external {
        _borrowFromSilo(_xaiAmount);
    }
    function test_repayTokenDebt(uint256 _xaiAmount) external {
        _repayTokenDebt(_xaiAmount);
    }
    function test_repayMaxTokenDebt() external {
        _repayMaxTokenDebt();
    }
    function test_depositToVault(uint256 _xaiAmount) external {
        _depositToVault(_xaiAmount);
    }
    function test_withdrawFromVault(uint256 _amount) external {
        _withdrawFromVault(_amount);
    }
    function test_withdrawAllFromVault() external {
        _withdrawAllFromVault();
    }
}