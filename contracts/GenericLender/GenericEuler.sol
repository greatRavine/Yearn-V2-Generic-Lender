// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    BaseStrategyInitializable,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
// import Euler interface
import {
    IEulerMarkets,
    IEulerEToken,
    IEuler
} from "../Interfaces/Euler/IEuler.sol";
// import Euler Staking Interface (based on SNX staking)
import {
    IBaseIRM
} from "../Interfaces/Euler/IBaseIRM.sol";
import {
    IStakingRewards
} from "../Interfaces/Euler/IStakingRewards.sol";
import "../Interfaces/Euler/IEulerSimpleLens.sol";
import "../Interfaces/Euler/RPow.sol";
import "./GenericLenderBase.sol";
import {ITradeFactory} from "../Interfaces/ySwaps/ITradeFactory.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

interface IBaseFee {
    function isCurrentBaseFeeAcceptable() external view returns (bool);
}


contract GenericEuler is GenericLenderBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    IEuler internal constant EULER = IEuler(0x27182842E098f60e3D576794A5bFFb0777E025d3);
    IEulerMarkets internal constant EMARKETS = IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    IEulerSimpleLens internal constant LENS = IEulerSimpleLens(0x5077B7642abF198b4a5b7C4BdCE4f03016C7089C);
    IERC20 internal constant EUL = IERC20(0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b);
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Set on _initialize
    IEulerEToken public eToken;
    IBaseIRM internal eulerIRM;

    // optionally enabled
    IStakingRewards public eStaking;

    // Constants 
    uint256 internal constant SECONDS_PER_YEAR = 365.2425 * 86400;
    uint256 internal constant RESERVE_FEE_SCALE = 4_000_000_000; // must fit into a uint32

    // operational stuff
    address public tradeFactory;
    address public keep3r;
    uint256 public rewardsDust;

    // initialisation and constructor
    constructor(
        address _strategy,
        string memory name
    ) public GenericLenderBase(_strategy, name) {
        _initialize();
    }
    function initialize() external {
        _initialize();
    }
    function _initialize() internal {
        require(address(eToken) == address(0), "GenericEuler already initialized");
        // getting correct eToken Contract (the token you get for lending collateral)
        eToken = IEulerEToken(EMARKETS.underlyingToEToken(address(want)));
    
        // approve EULER main contract
        want.safeApprove(address(EULER), type(uint256).max);

        // set interest rate module for apr estimation
        uint256 moduleID = EMARKETS.interestRateModel(address(want));
        eulerIRM = IBaseIRM(EULER.moduleIdToImplementation(moduleID));
    }

    // in USD scaled by 10**18 - just put how much dollar you need for harvest
    function setRewardsDust(uint256 _rdust) external management {
        rewardsDust = _rdust;
    }

    // enable Staking
    function activateStaking(address _stakingContract, uint256  _rdust) external management {
        //set Staking contract and approve
        require (!hasStaking(), "Staking already initialized");
        rewardsDust = _rdust;
        eStaking = IStakingRewards(_stakingContract);
        IERC20(address(eToken)).safeApprove(_stakingContract, type(uint).max);
        _depositStaking();
    }
    // Disable staking
    function deactivateStaking() external management {
        require(hasStaking(), "Staking is not enabled");
        _exitStaking();
        IERC20(address(eToken)).safeApprove(address(eStaking), 0);
        eStaking = IStakingRewards(address(0));
    }

    // borrowed from spalen0
    // https://github.com/spalen0/Yearn-V2-Generic-Lender/blob/c29eace1bf4a0b58d424b860eb6a605341507177/contracts/GenericLender/GenericAaveMorpho.sol#L92
    function cloneEulerLender(
        address _strategy,
        string memory _name
    ) external returns (address newLender) {
        newLender = _clone(_strategy, _name);
        GenericEuler(newLender).initialize();
    }

    function hasStaking() public view returns (bool) {
        return (address(eStaking) != address(0));
    }

    function setKeep3r(address _keep3r) external management {
        keep3r = _keep3r;
    }
    modifier keepers() {
        require(
            msg.sender == address(keep3r) ||
                msg.sender == address(strategy) ||
                msg.sender == vault.governance() ||
                msg.sender == vault.management(),
            "!keepers"
        );
        _;
    }



    //return current holdings
    function nav() external view override returns (uint256) {
        return _nav();
    }

    function _nav() internal view returns (uint256) {
        (,,,uint256 total) = getBalance();
        return total;
    }
    function getBalance() public view returns (uint256, uint256, uint256, uint256) {
        uint256 local = balanceOfWant();
        // staked in want
        uint256 staked = hasStaking() ? eToken.convertBalanceToUnderlying(eStaking.balanceOf(address(this))) : 0;
        // deposited into Euler lending (in want) - should be zero if Staking is enabled
        uint256 lent = eToken.balanceOfUnderlying(address(this));
        // total amount in want
        uint256 total = local.add(staked).add(lent);
        return (local,lent,staked,total);
    }

    function apr() external view override returns (uint256) {
        return _apr();
    }

    // scaled by 1e18
    function _apr() internal view returns (uint256) {
        return _lendingApr(0).add(_stakingApr(0));
    }

    function aprAfterDeposit(uint256 _amount) external view override  returns (uint256) {
        return _lendingApr(_amount).add(_stakingApr(_amount));
    }


    // calculate lending APR if you deposit _amount (in want)
    function _lendingApr(uint256 _amount) internal view returns (uint256) {
        if (_amount == 0) {
            (,, uint256 supplyAPY) = LENS.interestRates(address(want));
            return supplyAPY.div(1e9);
        } else {
            (,uint256 totalBalance, uint256 totalBorrow,)=LENS.getTotalSupplyAndDebts(address(want));
            //utilisation is scaled to 2**32 -> 100%
            uint32 utilisation = uint32(totalBorrow.mul(type(uint32).max).div(totalBalance.add(_amount)));
            //Scaling in RAY 1*10**27 == 100% apy
            uint256 estimatedBorrowSPY = uint256(eulerIRM.computeInterestRate(vault.token(), utilisation));
            uint256 supplyAPY = computeAPYs(estimatedBorrowSPY, totalBorrow ,totalBalance.add(_amount));
            return supplyAPY.div(1e9);
        }
    }

    // calculates staking APR if you deposit _amount (in want)
    function _stakingApr(uint256 _amount) internal view returns (uint256) {
        if (!hasStaking()) {
            return 0;
        }
        // EULunits per second
        uint256 rewardRateAdj = eStaking.periodFinish() > now ? eStaking.rewardRate() : 0;
        // total Want units staked
        uint256 totalWantStaked = eToken.convertBalanceToUnderlying(eStaking.totalSupply()).add(_amount);
        //weiPerEul / weiPerWant = WantPerEul
        (uint256 weiPerEul,,) = LENS.getPriceFull(address(EUL));
        (uint256 weiPerWant,,) = LENS.getPriceFull(address(want));
        // rewardsRate[EULunits/s] * weiPerEul[wei/(10**18 EULunits)]/weiPerWant[wei/(10**wantDecimals WANTunits)] * SECONDS_PER_YEAR[s] / TotalSupplyWant[WANTunits] * SCALING_FACTOR_1e18
        uint256 staking_apr = (10**uint256(vault.decimals())).mul(weiPerEul).mul(rewardRateAdj).mul(SECONDS_PER_YEAR).div(weiPerWant).div(totalWantStaked); // div(1e18).mul(SCALING_FACTOR_1e18)
        return staking_apr;
    }


    function weightedApr() external view override returns (uint256) {
        uint256 a = _apr();
        return a.mul(_nav());
    }

    // withdraw function ()
    function withdraw(uint256 _amount) external override management returns (uint256) {
        return _withdraw(_amount);
    }





    function _claimRewards() internal {
        eStaking.getReward();      
    }
    function getPendingRewards() external view returns (uint256){
        if (!hasStaking()) {
             return 0;
        }
        return eStaking.earned(address(this));
    }

    // Alternative with harvest triggers or can also be used with tradehandler!
    function harvest() external keepers {
        _claimRewards();
    }

    // comment out isBaseFeeAcceptable() and harvestTrigger if only used with tradehandler
    // check if the current baseFee is below our external target
    function isBaseFeeAcceptable() internal view returns (bool) {
        return IBaseFee(0xb5e1CAcB567d98faaDB60a1fD4820720141f064F).isCurrentBaseFeeAcceptable();
    }
    function harvestTrigger(uint256 /*callCost*/) external view returns(bool) {
        if(!hasStaking()) return false;
        if(!isBaseFeeAcceptable()) return false;
        if(earnedDollar() > rewardsDust) return true;
    }

    // scaled by 10**18
    function earnedDollar() public view returns (uint256) {
        (,,uint256 eulp) = LENS.getPriceFull(address(EUL));
        (,,uint256 usdcp) = LENS.getPriceFull(USDC);
        return eStaking.earned(address(this)).mul(eulp).div(usdcp);
    }

    function _withdraw(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        uint256 local = balanceOfWant();
        if (_amount > local) { 
            if (hasStaking()) {
                _withdrawStaking(_amount - local);
                _withdrawLending(type(uint256).max);
                //unstake what is needed and withdraw - we withdraw as much from lending as possible as we assume lent == 0 (if we have staking)
                // if lent > 0 - it is now 0 and our expectation holds true again
            } else {
                _withdrawLending(_amount - local); 
            }
            _amount = Math.min(_amount, balanceOfWant());
        }
        want.safeTransfer(address(strategy), _amount);
        return _amount;
    }

    function deposit() external override management {
        //deposit and stake all!
        _depositLending();
        _depositStaking();
    }


    //you cannot pass uint256.max (Eulers conversion math explodes) but you can pass a higher value than total holding to withdraw everything.
    function emergencyWithdraw(uint256 _amount) external override management {
        //withdraw
        if (_amount == 0) {
            return;
        }
        if (hasStaking()) {
            uint256 balance = eStaking.balanceOf(address(this));
            // for small values the conversion can turn out to be 0.
            uint256 eTokenAmount = eToken.convertUnderlyingToBalance(_amount);
            if (balance > 0 && eTokenAmount > 0) { 
                eStaking.withdraw(Math.min(eTokenAmount,balance));  
            }
        }
        _withdrawLending(_amount);
        want.safeTransfer(vault.governance(), balanceOfWant());
    }

    function withdrawAll() external override management returns (bool) {
        _exitStaking();
        _withdrawLending(type(uint256).max);
        uint256 looseBalance = balanceOfWant();
        want.safeTransfer(address(strategy), looseBalance);
        (,,,uint256 total) = getBalance();
        return(dust > total);
    }

    function hasAssets() external view override returns (bool) {
        (,,,uint256 total) = getBalance();
        return (total > dust);
    }
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        protected[0] = address(want);
        return protected;
    }


    // internal function to be called
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }


    //_amount in underlying 
    // withdrawStaking will withdraw as much as possible via exitStaking if amount > balance - cannot handle uint256.max!
    // no liquidity issues with staking possible
    function  _withdrawStaking(uint256 _amount) internal {
        uint256 balance = eStaking.balanceOf(address(this));
        // for small values the conversion can turn out to be 0.
        uint256 eTokenAmount = eToken.convertUnderlyingToBalance(_amount);
        if (balance == 0 || eTokenAmount == 0) { 
            return;
        }
        if (balance > eTokenAmount ){
            eStaking.withdraw(eTokenAmount);
            // emit WithdrawStaking(eTokenAmount, _amount);
        } else  {
            _exitStaking();
        }
    }
    // exitStaking removes all staked assets and claims rewards.
    function  _exitStaking() internal {
        if (!hasStaking() || eStaking.balanceOf(address(this)) == 0) {
            return;
        }
        eStaking.exit();
        // emit WithdrawStaking(balance, eToken.convertBalanceToUnderlying(balance));
    }
    //_amount in underlying!
    //withdrawLending withdraws as much as possible if _amount > balance or _amount > liquidity
    function  _withdrawLending(uint256 _amount) internal {
        // don't do anything if 0
        if (_amount == 0 || eToken.balanceOf(address(this)) == 0) {
            return;
        }
        // factor in liquidity of lending pool
        _amount = Math.min(want.balanceOf(address(EULER)), _amount);
        // factor in current balance
        uint256 balance = eToken.balanceOfUnderlying(address(this));
        if (balance > _amount ){
            eToken.withdraw(0, _amount);
        } else  {
            eToken.withdraw(0, type(uint256).max);
        }
    }
    //deposit as much as possible
    function  _depositStaking() internal {
        if (!hasStaking()) {
            return;
        }        
        uint256 balance = eToken.balanceOf(address(this));
        if (balance > 0) { 
            eStaking.stake(balance);
        }
    }
    //deposit as much as possible
    function  _depositLending() internal {
        uint256 balance = balanceOfWant();
        if (balance > 0) { 
            eToken.deposit(0, balance);
        }         
    }

    // compute APYs - borrowed from:
    // https://github.com/euler-xyz/euler-contracts/blob/6d1d7d11fc6cc74a92feded055315e562eaf9cb8/contracts/views/EulerSimpleLens.sol#L187
    function computeAPYs(uint256 borrowSPY, uint256 totalBorrows, uint256 totalBalancesUnderlying) internal view returns (uint256 supplyAPY) {
        uint256 supplySPY = totalBalancesUnderlying == 0 ? 0 : borrowSPY.mul(totalBorrows).div(totalBalancesUnderlying);
        supplySPY = supplySPY.mul(RESERVE_FEE_SCALE - EMARKETS.reserveFee(address(want))).div(RESERVE_FEE_SCALE);
        supplyAPY = RPow.rpow(supplySPY + 1e27, SECONDS_PER_YEAR, 10**27) - 1e27;
    }


   // ---------------------- YSWAPS FUNCTIONS ----------------------
    function setTradeFactory(address _tradeFactory) external onlyGovernance {
        if (tradeFactory != address(0)) {
            _removeTradeFactoryPermissions();
        }
        ITradeFactory tf = ITradeFactory(_tradeFactory);
        EUL.safeApprove(_tradeFactory, type(uint256).max);
        tf.enable(address(EUL), address(want));
        tradeFactory = _tradeFactory;
    }

    function removeTradeFactoryPermissions() external management {
        _removeTradeFactoryPermissions();
    }

    function _removeTradeFactoryPermissions() internal {
        ITradeFactory tf = ITradeFactory(tradeFactory);
        tf.disable(address(EUL), address(want));
        EUL.safeApprove(tradeFactory, 0);
        tradeFactory = address(0);
    }
}

