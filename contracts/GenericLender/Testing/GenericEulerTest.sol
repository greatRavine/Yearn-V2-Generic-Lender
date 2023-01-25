// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;



import "../../GenericLender/GenericEuler.sol";
contract GenericEulerTest is GenericEuler {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;


    // initialisation and constructor
    constructor(
        address _strategy,
        string memory name
    ) public GenericEuler(_strategy, name) {
    }

    function lendingApr(uint256 _amount) external view returns (uint256) {
        return _lendingApr(_amount);
    }

    function stakingApr(uint256 _amount) external view returns (uint256) {
        return _stakingApr(_amount);
    }
}