// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "../Interfaces/Morpho/ILens.sol";
import "../Interfaces/Morpho/IMorpho.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
interface IERC3156FlashBorrower {
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data) external returns (bytes32);
}

interface IERC3156FlashLender {
    function maxFlashLoan(address token) external view returns (uint256);
    function flashFee(address token, uint256 amount) external view returns (uint256);
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data) external returns (bool);
}


contract FlashloanAPR is IERC3156FlashBorrower {


    event CurrentBalance(uint256 _want, uint256 apr);
    address public constant _lender = address(0x07df2ad9878F8797B4055230bbAE5C808b8259b3);
    ILens internal constant LENS = ILens(0x507fA343d0A90786d86C7cd885f5C49263A91FF4);
    IMorpho internal constant MORPHO = IMorpho(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);
    uint256 public apr;
    uint256 public constant maxGasForMatching = 100000;

    event BorrowResult(address token, uint balance, uint fee, uint borrowIndex, address sender, address initiator);

    function setMaxAllowance(address token, address to) public returns (bool success) {
        (success,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, type(uint).max));

    }

    function testFlashBorrow(address lender, address receiver, address token, address aToken, uint256 amount) external {

        bytes memory data = abi.encode(receiver, token, amount, aToken);
        
        _borrow(lender, receiver, token, amount, data);

        assert(IERC20(token).balanceOf(receiver) == 0);
       
    }

    function onFlashLoan(address initiator, address token, uint256, uint256 fee, bytes calldata data) override external returns(bytes32) {
        (address receiver, address token, uint256 amounts, address  aToken) = 
            abi.decode(data, (address, address, uint256, address));
            
        setMaxAllowance(token, msg.sender);
        setMaxAllowance(token, address(MORPHO));


        _emitBorrowResult(token, fee, 0, initiator);

        MORPHO.supply(
            aToken,
            address(this),
            amounts,
            maxGasForMatching
        );
        apr = LENS.getCurrentUserSupplyRatePerYear(aToken, address(this));
        _emitBorrowResult(token, fee, 0, initiator);
        MORPHO.withdraw(aToken, type(uint256).max);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _borrow(address lender, address receiver, address token, uint amount, bytes memory data) internal {
        IERC3156FlashLender(lender).flashLoan(IERC3156FlashBorrower(receiver), token, amount, data);
    }

    function _emitBorrowResult(address token, uint fee, uint borrowIndex, address initiator) internal {
        emit BorrowResult(
            token,
            IERC20(token).balanceOf(address(this)),
            fee,
            borrowIndex,
            msg.sender,
            initiator
        );
    }
}