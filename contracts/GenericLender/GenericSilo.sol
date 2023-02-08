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
import {ISiloRepository} from "../Interfaces/Silo/ISiloRepository.sol";
import {IPriceProvidersRepository} from "../Interfaces/Silo/IPriceProvidersRepository.sol";

interface IBaseFee {
    function isCurrentBaseFeeAcceptable() external view returns (bool);
}

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
}

contract GenericSilo is GenericLenderBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;



    // Constants 
    uint256 internal constant SECONDS_PER_YEAR = 365.2425 * 86400;
    IERC20 public constant XAI = IERC20(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc);
    ISiloRepository public constant silorepository = ISiloRepository(0xd998C35B7900b344bbBe6555cc11576942Cf309d);
    ISiloLens public constant silolens = ISiloLens(0xf12C3758c1eC393704f0Db8537ef7F57368D92Ea);
    IPriceProvidersRepository public  priceprovider;
    ISilo public silo;
    VaultAPI public yvxai;
    //scaled by 10**18
    uint256 public liquidationThreshold;
    //scaled by 10**18
    uint256 internal constant SCALING_FACTOR = 10**18;
    uint256 public borrowFactor;
    uint256 public mockApr;




    // not used with claim rewards - only used for harvest with harvest trigger!
    // to be removed if harvest & harvest trigger are not used 
    uint256 public minEarnedToClaim;

    // operational stuff
    address public tradeFactory;
    address public keep3r;

    // events will be removed for prod
    event DepositCollateral (uint256 _token, uint256 _want);
    event WithdrawCollateral (uint256 _token, uint256 _want);
    event BorrowXAI (uint256 _token, uint256 _want);
    event RepayXAI (uint256 _token, uint256 _want);

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
        uint256 realborrowFactor;
        (realborrowFactor,liquidationThreshold,) = silorepository.assetConfigs(address(silo),address(want));
        borrowFactor = realborrowFactor.mul(99).div(100);
        yvxai = VaultAPI(_xaivault);
        XAI.safeApprove(address(yvxai), type(uint256).max);
        XAI.safeApprove(address(silo), type(uint256).max);
    }

    modifier keepers() {
        require(
            msg.sender == address(keep3r) ||
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

    function setKeep3r(address _keep3r) external management {
        keep3r = _keep3r;
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




    function _claimRewards() internal {    
    }

    // Alternative with harvest triggers or can also be used with tradehandler!
    function harvest() external keepers {
        _rebalanceDebt(deltaInDebt());
    }

    // comment out isBaseFeeAcceptable() and harvestTrigger if only used with tradehandler
    // check if the current baseFee is below our external target
    function isBaseFeeAcceptable() internal view returns (bool) {
        return IBaseFee(0xb5e1CAcB567d98faaDB60a1fD4820720141f064F).isCurrentBaseFeeAcceptable();
    }
    function harvestTrigger(uint256 /*callCost*/) external view returns(bool) {
        if(!isBaseFeeAcceptable()) return false;

    }





    function _withdraw(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        silo.accrueInterest(address(XAI));
        uint256 toLiquidate = valueInXai(_amount).add(deltaInDebt());
        _withdrawFromXaiVault(toLiquidate);
        _repayMaxTokenDebt();
        _withdrawFromSilo(_amount);
        want.safeTransfer(address(strategy), _amount); 
        return _amount;
        
    }

    function deposit() external override management {
        //deposit
        _depositToSilo();
        uint256 debt = balanceOfDebt();
        // in xai
        uint256 projectedDebt = valueInXai(balanceOfCollateral().mul(borrowFactor).div(SCALING_FACTOR));
        if (projectedDebt >= debt) {
        // borrow some and deposit
            uint256 amount = projectedDebt.sub(debt);
            _borrowFromSilo(amount);
            _depositToXaiVault(balanceOfXai());
        }
    }


    function emergencyWithdraw(uint256 _amount) external override management {
        if (_amount == 0) {
            return;
        }
        silo.accrueInterest(address(XAI));
        uint256 toLiquidate = valueInXai(_amount).add(deltaInDebt());
        _withdrawFromXaiVault(toLiquidate);
        _repayMaxTokenDebt();
        _withdrawFromSilo(_amount);
        want.safeTransfer(vault.governance(), _amount);
    }

    function withdrawAll() external override management returns (bool) {
        silo.accrueInterest(address(XAI));
        _withdrawAllFromXaiVault();
        _repayMaxTokenDebt();
        uint256 projectedCollateral = valueInWant(balanceOfDebt().mul(SCALING_FACTOR).div(borrowFactor));
        uint256 collateral = balanceOfCollateral();
        _withdrawFromSilo(collateral.sub(projectedCollateral));
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
        return silolens.debtBalanceOfUnderlying(silo, address(XAI), address(this));
    }
    // in shares
    function balanceOfXaiVaultShares() public view returns (uint256) {
        return yvxai.balanceOf(address(this));
    }
    // in xai
    function balanceOfXaiVaultInXai() public view returns (uint256) {
        return balanceOfXaiVaultShares().mul(10**18).div(yvxai.pricePerShare());
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

    // Deltas
    function deltaInCollateral() public view returns (uint256 debt) {
        uint256 projectedCollateral = valueInWant(balanceOfDebt().mul(SCALING_FACTOR).div(borrowFactor));
        uint256 collateral = balanceOfCollateral();
        debt = projectedCollateral > collateral ? projectedCollateral.sub(collateral) : 0;
    }
    function deltaInDebt() public view returns (uint256 debt) {
        uint256 projectedDebt = valueInXai(balanceOfCollateral().mul(borrowFactor).div(SCALING_FACTOR));
        uint256 currentDebt = balanceOfDebt();
        debt = currentDebt > projectedDebt ? currentDebt - projectedDebt : 0;
    }
    function reservesInDebt() public view returns (uint256 reserve) {
        uint256 projectedDebt = valueInXai(balanceOfCollateral().mul(liquidationThreshold).div(SCALING_FACTOR));
        reserve = projectedDebt.sub(balanceOfDebt());
    }    
    function reservesInCollateral() public view returns (uint256 reserve) {
        uint256 projectedCollateral = valueInWant(balanceOfDebt().mul(SCALING_FACTOR).div(liquidationThreshold));
        reserve = balanceOfCollateral().sub(projectedCollateral);
    }


    // ---------------------- Silo helper functions ----------------------

// internal functions

    function _rebalanceDebt(uint256 _amount) internal {
        _withdrawFromXaiVault(_amount);
        _repayTokenDebt(_amount);
    }

    function _depositToSilo() internal {
        uint256 local = balanceOfWant();
        if (local >0) {
            silo.deposit(address(want), local, true);
        }
    }

    function _withdrawFromSilo(uint256 _amount) internal {
        if (_amount == 0){
            return;
        }
        silo.withdraw(address(want), _amount, true);
    }
    function _borrowFromSilo(uint256 _xaiAmount) internal {
        _xaiAmount = Math.min(liquidity(), _xaiAmount);
        if (_xaiAmount > 0) {
            silo.borrow(address(XAI), _xaiAmount);
        }
    }

    function _repayTokenDebt(uint256 _xaiAmount) internal {
        silo.repay(address(XAI), _xaiAmount);
    }

    function _repayMaxTokenDebt() internal {
        // @note: We cannot pay more than loose balance or more than we owe
        _repayTokenDebt(Math.min(balanceOfXai(), balanceOfDebt()));
    }

    // ---------------------- IVault functions ----------------------

    function _depositToXaiVault(uint256 _xaiAmount) internal {
        uint256 amount = Math.min(balanceOfXai(),_xaiAmount);
        if (amount > 0) {
            yvxai.deposit(amount);
        }
    }

    function _withdrawFromXaiVault(uint256 _amount) internal {
        uint256 _sharesNeeded = _amount * 10 ** vault.decimals() / vault.pricePerShare();
        yvxai.withdraw(Math.min(balanceOfXaiVaultShares(), _sharesNeeded));
    }
    function _withdrawAllFromXaiVault() internal {
        yvxai.withdraw(balanceOfXaiVaultShares());
    }


    // @note: Manual function available to management to withdraw from vault and repay debt
    function manualWithdrawAndRepayDebt(uint256 _amount) external management {
        if(_amount > 0) {
            _withdrawFromXaiVault(_amount);
        }
        _repayMaxTokenDebt();
    }


}

