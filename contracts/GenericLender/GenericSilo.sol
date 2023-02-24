// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    BaseStrategyInitializable,
    StrategyParams,
    VaultAPI
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {
    Math
} from "@openzeppelin/contracts/math/Math.sol";
import "../Interfaces/Euler/RPow.sol";
import "./GenericLenderBase.sol";
import {ITradeFactory} from "../Interfaces/ySwaps/ITradeFactory.sol";
import {ISilo} from "../Interfaces/Silo/ISilo.sol";
import {ISiloLens} from "../Interfaces/Silo/ISiloLens.sol";
import {ISiloRepository} from "../Interfaces/Silo/ISiloRepository.sol";
import {IPriceProvidersRepository} from "../Interfaces/Silo/IPriceProvidersRepository.sol";
import {ISwapRouter} from "../Interfaces/UniswapInterfaces/V3/ISwapRouter.sol";

interface IBaseFee {
    function isCurrentBaseFeeAcceptable() external view returns (bool);
}

contract GenericSilo is GenericLenderBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Constants 
    uint256 internal constant SECONDS_PER_YEAR = 365.2425 * 86400;
    IERC20 public constant XAI = IERC20(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ISiloRepository public constant silorepository = ISiloRepository(0xd998C35B7900b344bbBe6555cc11576942Cf309d);
    ISiloLens public constant silolens = ISiloLens(0xEc7ef49D78Da8801C6f4E5c62912E3Bf08BD28C9);
    IPriceProvidersRepository public  priceprovider;
    ISilo public silo;
    VaultAPI public yvxai;
    ISwapRouter public constant uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24 public constant poolFee030 = 3000;
    uint24 public constant poolFee005 = 500;
    uint24 public constant poolFee001 = 100;
    uint24 public constant poolFee100 = 10000;


    //scaled by 10**18
    uint256 public liquidationThreshold;
    //scaled by 10**18
    uint256 internal constant SCALING_FACTOR = 10**18;
    uint256 public borrowFactor;
    uint256 public realBorrowFactor;
    uint256 public mockApr;

    // operational stuff
    address public keeper;

    // initialisation and constructor - passing staking contracts as argument 
    constructor(
        address _strategy,
        string memory name,
        address _xaivault
    ) public GenericLenderBase(_strategy, name) {
        _initialize(_xaivault);
    }

    function initialize(address _xaivault) external {
        _initialize(_xaivault);
    }
    function _initialize(address _xaivault) internal {
        if (address(want) == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) {
            silo = ISilo(silorepository.getSilo(address(XAI)));
        } else {
            silo = ISilo(silorepository.getSilo(address(want)));
        }
        want.safeApprove(address(silo), type(uint256).max);
        priceprovider = IPriceProvidersRepository(silorepository.priceProvidersRepository());
        mockApr = 0;
        dust = 500 * 10**18; // can be changed with setDust inherited from GenericLenderBase
        (realBorrowFactor,liquidationThreshold,) = silorepository.assetConfigs(address(silo),address(want));
        borrowFactor = realBorrowFactor.mul(99).div(100);
        yvxai = VaultAPI(_xaivault);
        XAI.safeApprove(address(yvxai), type(uint256).max);
        XAI.safeApprove(address(silo), type(uint256).max);
        
    }

    modifier keepers() {
        require(
            msg.sender == address(keeper) ||
                msg.sender == address(strategy) ||
                msg.sender == vault.governance() ||
                msg.sender == IBaseStrategy(strategy).strategist(),
            "!keepers"
        );
        _;
    }

    function setApr(uint256 _mockApr) external management {
        mockApr=_mockApr;
    }


    // borrowed from spalen0
    // https://github.com/spalen0/Yearn-V2-Generic-Lender/blob/c29eace1bf4a0b58d424b860eb6a605341507177/contracts/GenericLender/GenericAaveMorpho.sol#L92
    function cloneSiloLender(
        address _strategy,
        string memory _name,
        address _xaivault
    ) external returns (address newLender) {
        newLender = _clone(_strategy, _name);
        GenericSilo(newLender).initialize(_xaivault);
    }

    function setKeeper(address _keeper) external management {
        keeper = _keeper;
    }

    //return current holdings
    function nav() external view override returns (uint256) {
        return _nav();
    }

    function _nav() internal view returns (uint256) {
        uint256 total =balanceOfWant().add(balanceOfCollateral()).add(valueInWant(balanceOfXaiVaultInXai().add(balanceOfXai()))).sub(valueInWant(balanceOfDebt()));
        return total;
    }


    function apr() external view override returns (uint256) {
        return _apr();
    }

    // scaled by 1e18
    function _apr() internal view returns (uint256) {
        //@dev use yvXAI vault to calculate apy over time.
        // xaiVault.totalSupply() -> #yvXAI
        // xaiVault.totalAssets() -> #XAI
        return mockApr;
    }

    function aprAfterDeposit(uint256 _amount) external view override  returns (uint256) {
        //if there is not enough XAI to borrow, report 0 apy, as we cannot deploy the captial
        if (valueInXai(_amount).mul(borrowFactor).div(SCALING_FACTOR) >= liquidity()) {
            return 0;
        } else {
            return mockApr;
        }
    }

    function weightedApr() external view override returns (uint256) {
        uint256 a = _apr();
        return a.mul(_nav());
    }

    // withdraw function ()
    function withdraw(uint256 _amount) external override management returns (uint256) {
        // only claim 200 EUL or more - staking exit will also claim if you withdraw the whole balance
        // you can withdraw 0 to trigger rewards claiming
        return _withdraw(_amount);
    }

    function tend() external keepers {
        // get how much interest we need to payback
        uint toRebalance = deltaInDebt();
        // check if we have enough profits to withdraw at least dust
        uint256 _threshold = balanceOfDebt().add(dust).add(toRebalance);
        uint256 _xaiBalance = balanceOfXaiVaultInXai();
        // check if we have enough profits to withdraw at least dust - else just rebalance the position
        uint256 toWithdraw = (_xaiBalance > _threshold) ? _xaiBalance - _threshold : toRebalance;
        if (_xaiBalance > _threshold) {
            _withdrawFromXaiVault(_xaiBalance - _threshold);
            _repayTokenDebt(toRebalance);
            _sellXaiForWant(balanceOfXai());
            _deposit();
        } else {
            _withdrawFromXaiVault(toRebalance);
            _repayMaxTokenDebt();
        }
    }

    
    // comment out isBaseFeeAcceptable() and harvestTrigger if only used with tradehandler
    // check if the current baseFee is below our external target
    function isBaseFeeAcceptable() internal view returns (bool) {
        return IBaseFee(0xb5e1CAcB567d98faaDB60a1fD4820720141f064F).isCurrentBaseFeeAcceptable();
    }
    
    function tendTrigger(uint256 /*callCost*/) external view returns(bool) {
        //1% buffer before liquidation - no matter what gas fees are, we need to rebalance.
        if (getCurrentLTV() > (liquidationThreshold - 10**16)){
            return true;
        }
        if(isBaseFeeAcceptable() && getCurrentLTV() > realBorrowFactor) {
            return true;
        }
    }

    // _amount in Want
    function _withdraw(uint256 _amount) internal returns (uint256) {
        // don't do anything for 0
        if (_amount == 0) {
            return 0;
        }
        // if we don't have enough, check if we can take profits
        if (_amount > balanceOfWant()){
            _getSurplus(_amount.sub(balanceOfWant()));
        }
        // if we still don't have enough, unwind your borrow position
        // if yvXAI vault holds less tokens than our debt we may not be able to unwind completely
        if (_amount > balanceOfWant()){
            _unwind(_amount.sub(balanceOfWant()));
        }
        _amount=Math.min(_amount,balanceOfWant());
        want.safeTransfer(address(strategy), _amount); 
        return _amount;
    }
    // _amount in Want
    function _getSurplus(uint256 _amount) internal {
        _amount = valueInXai(_amount);
        // only if the yvXAI hold more than our debt, we can take off the profits
        uint256 toSellOffinXai = (balanceOfXaiVaultInXai() > balanceOfDebt()) ? Math.min(_amount,balanceOfXaiVaultInXai().sub(balanceOfDebt())) : 0;
        // we only do it if the profit is larger than dust
        if (toSellOffinXai > dust) {
            _withdrawFromXaiVault(toSellOffinXai);
            _sellXaiForWant(toSellOffinXai);
        }       
    }

    // _amount in Want
    function _unwind(uint256 _amount) internal {
        uint256 toLiquidate = valueInXai(_amount).mul(realBorrowFactor).div(SCALING_FACTOR).add(deltaInDebt());
        _withdrawFromXaiVault(toLiquidate);
        _repayMaxTokenDebt();
        // Collateral - Ratio
        uint256 toWithdraw = Math.min(balanceOfCollateral().sub(valueInWant(balanceOfDebt()).mul(SCALING_FACTOR).div(borrowFactor)), _amount);
        _withdrawFromSilo(toWithdraw); 
    }

    function deposit() external override management {
        //deposit
        _deposit();
    }
    function _deposit() internal {
        _depositToSilo();
        uint256 debt = balanceOfDebt();
        // in xai
        uint256 projectedDebt = valueInXai(balanceOfCollateral().mul(borrowFactor).div(SCALING_FACTOR));
        if (projectedDebt >= debt) {
        // borrow some and deposit
            uint256 amount = projectedDebt.sub(debt);
            _depositToXaiVault(_borrowFromSilo(amount));
        }
    }


    function emergencyWithdraw(uint256 _amount) external override management {
        if (_amount == 0) {
            return;
        }
        if (_amount > balanceOfWant()){
            _getSurplus(_amount.sub(balanceOfWant()));
        }
        if (_amount > balanceOfWant()){
            _unwind(_amount.sub(balanceOfWant()));
        }
        want.safeTransfer(vault.governance(), _amount);
    }

    function withdrawAll() external override management returns (bool) {
        _withdrawAllFromXaiVault();
        uint256 localXai = balanceOfXai();
        uint256 debt = balanceOfDebt();
        uint256 local = balanceOfWant();
        if (debt > localXai) {
            uint256 missingXai = debt - localXai;
            if (local > 0 && valueInXai(local) > missingXai) {
                _sellWantForXai(missingXai);
                _repayMaxTokenDebt();
            }
            _withdrawFromSilo(deltaInCollateral());
        } else {
            _repayMaxTokenDebt();
            _withdrawFromSilo(balanceOfCollateral());
            _sellXaiForWant(balanceOfXai());
        }
        uint256 looseBalance = balanceOfWant();
        want.safeTransfer(address(strategy), looseBalance);
        return !_hasAssets();
    }

    function hasAssets() external view override returns (bool) {
        return _hasAssets();
    }

    function _hasAssets() internal view returns (bool) {
        return (balanceOfWant() > 0 || balanceOfCollateral() > 0 ||  balanceOfXaiVaultShares() > 0 || balanceOfXai() > 0);
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        return protected;
    }



// ---------------------- HELPER AND UTILITY FUNCTIONS ----------------------
    // in want
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }
    // in want
    function balanceOfCollateral() public view returns (uint256) {
        return silolens.collateralBalanceOfUnderlying(silo, address(want), address(this));
    }
    // in xai
    function balanceOfXai() public view returns (uint256) {
        return XAI.balanceOf(address(this));
    }

    // in xai
    function liquidity() public view returns (uint256) {
        return silo.liquidity(address(XAI));
    }

    // in xai
    function balanceOfDebt() public view returns (uint256) {
        return silolens.getBorrowAmount(silo, address(XAI), address(this), now + 1);
    }
    // in shares
    function balanceOfXaiVaultShares() public view returns (uint256) {
        return yvxai.balanceOf(address(this));
    }
    // in xai
    function balanceOfXaiVaultInXai() public view returns (uint256) {
        return balanceOfXaiVaultShares().mul(yvxai.pricePerShare()).div(10**18);
    }

    // calculate xai from want
    function valueInXai(uint256 _amount) public view returns (uint256) {
        return _amount.mul(10**18).mul(priceprovider.getPrice(address(want))).div(priceprovider.getPrice(address(XAI))).div(10**vault.decimals());
    }
    // calculate want from xai
    function valueInWant(uint256 _amount) public view returns (uint256) {
        return _amount.mul(10**vault.decimals()).mul(priceprovider.getPrice(address(XAI))).div(priceprovider.getPrice(address(want))).div(10**18);
    }

    function getCurrentLTV() public view returns (uint256) {
        return silolens.getUserLTV(silo,address(this));
    }


    function deltaInDebt() public view returns (uint256 debt) {
        uint256 projectedDebt = valueInXai(balanceOfCollateral().mul(borrowFactor).div(SCALING_FACTOR));
        uint256 currentDebt = balanceOfDebt();
        debt = currentDebt > projectedDebt ? currentDebt - projectedDebt : 0;
    }
    function deltaInCollateral() public view returns (uint256 delta) {
        uint256 projectedCollateral = valueInWant(balanceOfDebt().mul(SCALING_FACTOR).div(borrowFactor));
        uint256 currentCollateral = balanceOfCollateral();
        delta = projectedCollateral > currentCollateral ? projectedCollateral - currentCollateral : 0;
    }

    // ---------------------- Silo helper functions ----------------------

// internal functions



    function _depositToSilo() internal {
        uint256 local = balanceOfWant();
        if (local > 0) {
            silo.deposit(address(want), local, true);
        }
    }

    function _withdrawFromSilo(uint256 _amount) internal {
        if (_amount == 0){
            return;
        }
        silo.withdraw(address(want), _amount, true);
    }
    function _borrowFromSilo(uint256 _xaiAmount) internal returns (uint256 borrowed) {
        _xaiAmount = Math.min(liquidity(), _xaiAmount);
        if (_xaiAmount > 0) {
            (borrowed,) = silo.borrow(address(XAI), _xaiAmount);
        }
    }

    function _repayTokenDebt(uint256 _xaiAmount) internal {
        uint256 toRepay = Math.min(_xaiAmount, balanceOfDebt());
        if (toRepay > 0) {
            silo.repay(address(XAI), toRepay);
        }
    }

    function _repayMaxTokenDebt() internal {
        // @note: We cannot pay more than loose balance or more than we owe
        _repayTokenDebt(balanceOfXai());
        uint256 remaining = balanceOfXai();
        if (remaining > 0) {
            _sellXaiForWant(remaining);
        }
    }

    // ---------------------- IVault functions ----------------------

    // Deposit the minimum of (1) the amount of XAI requested to be deposited, 
    // and (2) the amount of XAI that the contract currently holds.
    // If it has enough XAI, it deposits the amount requested. If it doesn't have enough XAI,
    // it deposits the amount it currently holds.

    function _depositToXaiVault(uint256 _xaiAmount) internal {
        uint256 amount = Math.min(balanceOfXai(),_xaiAmount);
        if (amount > 0) {
            yvxai.deposit(amount);
        }
    }

    function _withdrawFromXaiVault(uint256 _amount) internal {
        uint256 _shares = balanceOfXaiVaultShares();
        if (_amount > 0 && _shares > 0) {
            yvxai.withdraw(Math.min(_shares, _amount * 10 ** vault.decimals() / vault.pricePerShare()));
        }
    }
    function _withdrawAllFromXaiVault() internal {
        uint256 amount = balanceOfXaiVaultShares();
        if (amount > 0) {       
            yvxai.withdraw(amount);
        }
    }


    // @note: Manual function available to management to withdraw from vault and repay debt
    function manualWithdrawAndRepayDebt(uint256 _amount) external management {
        if(_amount > 0) {
            _withdrawFromXaiVault(_amount);
        }
        _repayMaxTokenDebt();
    }

// needed for liqidation 
    function _sellWantForXai(uint256 _amount) internal {
        uint256 maxIn = Math.min(valueInWant(_amount).mul(105).div(100),balanceOfWant());
        // only execute if there is anything to swap
        if (maxIn > 0) {
            if (address(want) == address(USDC)){
                ISwapRouter.ExactOutputSingleParams memory params =
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: address(USDC),
                    tokenOut: address(XAI),
                    fee: poolFee005,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: _amount,
                    amountInMaximum: maxIn,
                    sqrtPriceLimitX96: 0
                });
                // The call to `exactInputSingle` executes the swap.
                want.safeApprove(address(uniswapRouter), maxIn);
                uniswapRouter.exactOutputSingle(params);
            } else {
                ISwapRouter.ExactOutputParams memory params =
                ISwapRouter.ExactOutputParams({
                    path: abi.encodePacked(address(XAI), poolFee005, address(USDC), poolFee005, address(want)),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: _amount,
                    amountInMaximum: maxIn
                });
                // Executes the swap.
                want.safeApprove(address(uniswapRouter), maxIn);
                uniswapRouter.exactOutput(params);
            }
        }
    }
    function _sellXaiForWant(uint256 _amount) internal {
        // only execute if there is anything to swap
        uint256 maxIn = Math.min(_amount,balanceOfXai());
        uint256 minOut = valueInWant(maxIn).mul(95).div(100);
        if (maxIn > 0) {
            if (address(want) == address(USDC)){
                ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(XAI),
                    tokenOut: address(USDC),
                    fee: poolFee005,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: maxIn,
                    amountOutMinimum: minOut,
                    sqrtPriceLimitX96: 0
                });
                // The call to `exactInputSingle` executes the swap.
                XAI.safeApprove(address(uniswapRouter), maxIn);
                uniswapRouter.exactInputSingle(params);
            } else {
                ISwapRouter.ExactInputParams memory params =
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(address(XAI), poolFee005, address(USDC), poolFee005, address(want)),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: maxIn,
                    amountOutMinimum: minOut
                });
                // Executes the swap.
                XAI.safeApprove(address(uniswapRouter), maxIn);
                uniswapRouter.exactInput(params);
                }
        }
    }
}

