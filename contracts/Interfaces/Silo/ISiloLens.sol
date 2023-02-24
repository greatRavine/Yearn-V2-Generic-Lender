// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import {ISilo} from "./ISilo.sol";
interface ISiloLens {
    function totalDeposits(ISilo _silo, address _asset) external view returns (uint256);
    function collateralOnlyDeposits(ISilo _silo, address _asset) external view returns (uint256);
    function getUserLTV(ISilo _silo, address _user) external view returns (uint256 userLTV);
    function debtBalanceOfUnderlying(ISilo _silo, address _asset, address _user) external view returns (uint256);
    function calculateBorrowValue(ISilo _silo, address _user, address _asset) external view returns (uint256);
    function getUserLiquidationThreshold(ISilo _silo, address _user) external view returns (uint256);
    function getUserMaximumLTV(ISilo _silo, address _user) external view returns (uint256);
    function getUtilization(ISilo _silo, address _asset) external view returns (uint256);
    function borrowAPY(ISilo _silo, address _asset) external view returns (uint256);
    function collateralBalanceOfUnderlying(ISilo _silo, address _asset, address _user) external view returns (uint256);
    function calculateCollateralValue(ISilo _silo, address _user, address _asset) external view returns (uint256);
    function balanceOfUnderlying(uint256 _assetTotalDeposits, address _shareToken, address _user) external view returns (uint256);
    function getBorrowAmount(ISilo _silo, address _asset, address _user, uint256 _timestamp) external view returns (uint256);
    function getDepositAmount(ISilo _silo, address _asset, address _user, uint256 _timestamp) external view returns (uint256);

}
