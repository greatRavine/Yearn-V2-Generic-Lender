// SPDX-License-Identifier: MIT
// changed from 0.8.0 to >=0.5.0 - shouldn't be an issue with only the interface
pragma solidity >=0.5.0;
// added for consistency - shouldn't be an issue with only the interface
pragma experimental ABIEncoderV2;

// Euler Flashloan lender = 0x07df2ad9878F8797B4055230bbAE5C808b8259b3
interface IERC3156FlashBorrower {
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data) external returns (bytes32);
}

interface IERC3156FlashLender {
    function maxFlashLoan(address token) external view returns (uint256);
    function flashFee(address token, uint256 amount) external view returns (uint256);
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data) external returns (bool);
}