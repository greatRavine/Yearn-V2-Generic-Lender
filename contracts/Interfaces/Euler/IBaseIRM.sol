// SPDX-License-Identifier: MIT
// changed from 0.8.0 to >=0.5.0 - shouldn't be an issue with only the interface
pragma solidity >=0.5.0;
// added for consistency - shouldn't be an issue with only the interface
pragma experimental ABIEncoderV2;
interface IBaseIRM {
    function baseRate() external view returns (uint256);
    function slope1() external view returns (uint256);
    function slope2() external view returns (uint256);
    function kink() external view returns (uint256);
    function computeInterestRate(address underlying, uint32 utilisation) external view returns (int96);
}