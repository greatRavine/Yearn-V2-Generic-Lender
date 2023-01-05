// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;
interface IEulerSimpleLens {
    // Not complete! https://github.com/euler-xyz/euler-contracts/blob/master/contracts/views/EulerSimpleLens.sol
    // Contract: 0xAF68CFba29D0e15490236A5631cA9497e035CD39
    // underlying -> interest rate
    function interestRates(address underlying) external view returns (uint borrowSPY, uint borrowAPY, uint supplyAPY);
    // liability, collateral, health score
    function getAccountStatus(address account) external view returns (uint collateralValue, uint liabilityValue, uint healthScore);
    // prices
    function getPriceFull(address underlying) external view returns (uint twap, uint twapPeriod, uint currPrice);
    // Debt owed by a particular account, in underlying units
    function getDTokenBalance(address underlying, address account) external view returns (uint256);
    // Balance of a particular account, in underlying units (increases as interest is earned)
    function getETokenBalance(address underlying, address account) external view returns (uint256);
    // approvals
    function getEulerAccountAllowance(address underlying, address account) external view returns (uint256);
     // total supply, total debts
    function getTotalSupplyAndDebts(address underlying) external view returns (uint poolSize, uint totalBalances, uint totalBorrows, uint reserveBalance);
    // compute APYs
    function computeAPYs(uint borrowSPY, uint totalBorrows, uint totalBalancesUnderlying, uint32 _reserveFee) external pure returns (uint borrowAPY, uint supplyAPY);
}