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

interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

contract GenericEuler is GenericLenderBase {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    // Mainnet - depending on WANT token!
    // "stakingRewards_eUSDC": "0xE5aFE81e63f0A52a3a03B922b30f73B8ce74D570",
    // "stakingRewards_eUSDT": "0x7882F919e3acCa984babd70529100F937d90F860",
    // "stakingRewards_eWETH": "0x229443bf7F1297192394B7127427DB172a5bDe9E"
    address internal constant EULER = address(0x27182842E098f60e3D576794A5bFFb0777E025d3);
    IEulerMarkets internal constant eMarkets = IEulerMarkets(address(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3));
    IEulerSimpleLens internal constant LENS = IEulerSimpleLens(address(0x5077B7642abF198b4a5b7C4BdCE4f03016C7089C));
    IERC20 internal constant EUL = IERC20(address(0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b));
    // Set on _initialize
    IEulerEToken public eToken;
    IStakingRewards public eStaking;
    IBaseIRM internal eulerIRM;
    uint8 private wantDecimals;

    // Constants 
    uint256 internal constant SECONDS_PER_YEAR = 365.2425 * 86400;
    uint256 internal constant RESERVE_FEE_SCALE = 4_000_000_000; // must fit into a uint32
    uint256 public _minEarnedtoClaim = 2 * 1e20;

    // operational stuff
    address public tradeFactory;
    address public keep3r;

    event DepositStaking (uint256 _token, uint256 _want);
    event DepositLending (uint256 _token, uint256 _want);
    event WithdrawStaking (uint256 _token, uint256 _want);
    event WithdrawLending (uint256 _token, uint256 _want);

    // initialisation and constructor - passing staking contracts as argument 
    constructor(
        address _strategy,
        string memory name,
        address _stakingContract
    ) public GenericLenderBase(_strategy, name) {
        _initialize(_stakingContract);
    }
    function initialize(address _stakingContract) external {
        _initialize(_stakingContract);
    }
    function _initialize(address _stakingContract) internal {
        require(
            address(eStaking) == address(0),
            "GenericEulerLendnStake already initialized"
        );

        //Staking contracts
        eStaking = IStakingRewards(address(_stakingContract));
        // getting correct eToken Contract (the token you get for lending collateral)
        eToken = IEulerEToken(address(eMarkets.underlyingToEToken(address(want))));
        // approve staking contract for the eToken
        IERC20(address(eToken)).safeApprove(address(_stakingContract), type(uint).max); 
        // approve EULER main contract
        want.safeApprove(address(EULER), type(uint256).max);

        // decimals are necessary apr calculation
        wantDecimals = IERC20Metadata(address(want)).decimals();
        // set interest rate module for apr estimation
        uint256 moduleID = eMarkets.interestRateModel(address(want));
        IEuler euler = IEuler(EULER);
        eulerIRM = IBaseIRM(euler.moduleIdToImplementation(moduleID));
    }

    // borrowed from spalen0
    // https://github.com/spalen0/Yearn-V2-Generic-Lender/blob/c29eace1bf4a0b58d424b860eb6a605341507177/contracts/GenericLender/GenericAaveMorpho.sol#L92
    function cloneEulerLender(
        address _strategy,
        string memory _name,
        address _stakingContract
    ) external returns (address newLender) {
        newLender = _clone(_strategy, _name);
        GenericEuler(newLender).initialize(_stakingContract);
    }

    function setKeep3r(address _keep3r) external management {
        keep3r = _keep3r;
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



    //return current holdings
    function nav() external view override returns (uint256) {
        return _nav();
    }

    function _nav() internal view returns (uint256) {
        (,,,uint256 total) = getBalance();
        return total;
    }
    function getBalance() public view returns (uint256, uint256, uint256, uint256) {
        uint256 local = want.balanceOf(address(this));
        // staked in want
        uint256 staked = eToken.convertBalanceToUnderlying(eStaking.balanceOf(address(this)));
        // lent in want - should be zero
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
        // Only supply APY - staking not included - haven't found a clean way to get staking apr
        // RAY(1e27)
        uint256 lending_apr = _lendingApr(0); 
        uint256 staking_apr = _stakingApr(0);
        return lending_apr.add(staking_apr);
    }

    function aprAfterDeposit(uint256 _amount) external view override  returns (uint256) {
        uint256 lending_apr = _lendingApr(_amount);
        uint256 staking_apr = _stakingApr(_amount);
        return lending_apr.add(staking_apr);
    }


    // calculate lending APR if you deposit _amount (in want)
    function _lendingApr(uint256 _amount) public view returns (uint256) {
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
    function _stakingApr(uint256 _amount) public view returns (uint256) {
        // EULunits per second
        uint256 rewardRateAdj = eStaking.periodFinish() >= now ? eStaking.rewardRate() : 0;
        // total Want units staked
        uint256 totalWantStaked = eToken.convertBalanceToUnderlying(eStaking.totalSupply()).add(_amount);
        //weiPerEul / weiPerWant = WantPerEul :)
        (uint256 weiPerEul,,) = LENS.getPriceFull(address(EUL));
        (uint256 weiPerWant,,) = LENS.getPriceFull(address(want));
        // rewardsRate[EULunits/s] * weiPerEul[wei/(10**18 EULunits)]/weiPerWant[wei/(10**wantDecimals WANTunits)] * SECONDS_PER_YEAR[s] / TotalSupplyWant[WANTunits] * SCALING_FACTOR_1e18
        uint256 staking_apr = (10**uint256(wantDecimals)).mul(weiPerEul).mul(rewardRateAdj).mul(SECONDS_PER_YEAR).div(weiPerWant).div(totalWantStaked); // div(1e18).mul(SCALING_FACTOR_1e18)
        return staking_apr;
    }


    function weightedApr() external view override returns (uint256) {
        uint256 a = _apr();
        return a.mul(_nav());
    }

    // withdraw function ()
    function withdraw(uint256 _amount) external override management returns (uint256) {
        // only claim 200 EUL or more - staking exit will also claim if you withdraw the whole balance
        // you can withdraw 0 to trigger rewards claiming
        if (eStaking.earned(address(this)) > _minEarnedtoClaim) {
            eStaking.getReward();
        }
        return _withdraw(_amount);
    }
    function _withdraw(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        uint256 local = want.balanceOf(address(this));
        // how much is in staked or lent out - in general we assume lent out is 0 -> all is staked
        // calculate how much to unstake
        uint256 toUnwind = _amount > local ? _amount - local : 0;
        uint256 toFreeETokens = eToken.convertUnderlyingToBalance(toUnwind);
        //unstake ToUnwind and withdraw - we withdraw as much as possible as we assume lent == 0
        // if lent > 0 - it is now 0 and our expectation hold true again
        _withdrawStaking(toFreeETokens);
        _withdrawLending(type(uint256).max);
        uint256 looseBalance = want.balanceOf(address(this));
        want.safeTransfer(address(strategy), looseBalance);
        return looseBalance;
    }

    function deposit() external override management {
        //deposit and stake all!
        _depositLending(type(uint256).max);
        _depositStaking(type(uint256).max);
    }


    function emergencyWithdraw(uint256 _amount) external override management {
        //withdraw
        _withdraw(_amount);
    }

    function withdrawAll() external override management returns (bool) {
        _exitStaking();
        _withdrawLending(type(uint256).max);
        uint256 looseBalance = want.balanceOf(address(this));
        want.safeTransfer(address(strategy), looseBalance);
        (uint256 alocal,,,uint256 atotal) = getBalance();
        return(atotal == 0);
    }

    function hasAssets() external view override returns (bool) {
        (,,,uint256 total) = getBalance();
        return (total > 0);
    }
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        protected[0]= address(eToken);
        protected[1] = address(eStaking);
        protected[2] = address(EUL);
        return protected;
    }


// Internal funtions
    // internal function to be called
    // withdrawStaking will withdraw as much as possible if amount > balance
    // no liquidity issues with staking possible
    function  _withdrawStaking(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        uint256 balance = eStaking.balanceOf(address(this));
        if (balance > _amount ){
            eStaking.withdraw(_amount);
            emit WithdrawStaking(_amount, eToken.convertBalanceToUnderlying(_amount));
        } else  {
            _exitStaking();
        }
    }
    function  _exitStaking() internal {
        uint256 balance = eStaking.balanceOf(address(this));
        if (balance > 0){
            eStaking.exit();
            emit WithdrawStaking(balance, eToken.convertBalanceToUnderlying(balance));
        }
    }
    //_amount in underlying!
    //withdrawLending withdraws as much as possible if _amount > balance or _amount > liquidity
    function  _withdrawLending(uint256 _amount) internal {
        // don't do anything if 0
        if (_amount == 0) {
            return;
        }
        // don't do anythin if balance 0
        uint256 eTokenBalance = eToken.balanceOf(address(this));
        if (eTokenBalance == 0) { 
            return;
        }
        // factor in liquidity of lending pool
        uint256 liquidity = IERC20(address(want)).balanceOf(EULER);
        if (_amount > liquidity) {
            _amount = liquidity;
        }
        // factor in current balance
        uint256 balance = eToken.balanceOfUnderlying(address(this));
        if (balance > _amount ){
            eToken.withdraw(0, _amount);
            emit WithdrawLending(eToken.convertUnderlyingToBalance(_amount), _amount);
        } else  {
            eToken.withdraw(0, type(uint256).max);
            emit WithdrawLending(eTokenBalance, balance);
 
        }
    }
    //deposit as much as possible if _amount > balance
    function  _depositStaking(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        uint256 balance = eToken.balanceOf(address(this));
        if (balance == 0) { 
            return;
        }
        if (balance >= _amount) {
             eStaking.stake(_amount);
             emit DepositStaking(_amount, eToken.convertBalanceToUnderlying(_amount));     
        } else {
            eStaking.stake(balance);
            emit DepositStaking(balance, eToken.convertBalanceToUnderlying(balance));
        }
    }
    //deposit as much as possible if _amount > balance
    function  _depositLending(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        uint256 balance = want.balanceOf(address(this));
        if (balance == 0) { 
            return;
        }
        if (balance >= _amount) {
            eToken.deposit(0, _amount);
            emit DepositLending(eToken.convertUnderlyingToBalance(_amount), _amount);
        } else {
            eToken.deposit(0, balance);
            emit DepositLending(eToken.convertUnderlyingToBalance(balance), balance);  
        }    
    }
    // compute APYs - borrowed from:
    // https://github.com/euler-xyz/euler-contracts/blob/6d1d7d11fc6cc74a92feded055315e562eaf9cb8/contracts/views/EulerSimpleLens.sol#L187
    function computeAPYs(uint256 borrowSPY, uint256 totalBorrows, uint256 totalBalancesUnderlying) internal view returns (uint256 supplyAPY) {
        uint256 supplySPY = totalBalancesUnderlying == 0 ? 0 : borrowSPY.mul(totalBorrows).div(totalBalancesUnderlying);
        supplySPY = supplySPY.mul(RESERVE_FEE_SCALE - eMarkets.reserveFee(address(want))).div(RESERVE_FEE_SCALE);
        supplyAPY = RPow.rpow(supplySPY + 1e27, SECONDS_PER_YEAR, 10**27) - 1e27;
    }

   // ---------------------- YSWAPS FUNCTIONS ----------------------
    function setTradeFactory(address _tradeFactory) external onlyGovernance {
        if (tradeFactory != address(0)) {
            _removeTradeFactoryPermissions();
        }

        ITradeFactory tf = ITradeFactory(_tradeFactory);

        IERC20(EUL).safeApprove(_tradeFactory, type(uint256).max);
        tf.enable(address(EUL), address(want));
        
        tradeFactory = _tradeFactory;
    }

    function removeTradeFactoryPermissions() external management {
        _removeTradeFactoryPermissions();
    }

    function _removeTradeFactoryPermissions() internal {
        IERC20(EUL).safeApprove(tradeFactory, 0);
        
        tradeFactory = address(0);
    }

    // Recovery & intervention functions
    function recoveryUnstake(uint256 _amount) external management {
        eStaking.withdraw(_amount);
    }
    function recoveryStake(uint256 _amount) external management {
        eStaking.stake(_amount);
    }
    function recoveryWithdraw(uint256 _amount) external management {
        eToken.withdraw(0, _amount);
    }
    function recoveryDeposit(uint256 _amount) external management {
        eToken.deposit(0, _amount);
    }
    function recoveryGetRewards() external management {
        eStaking.getReward();
    }
    function reapprove() external management {
        IERC20(address(eToken)).safeApprove(address(eStaking), type(uint).max); 
        // approve EULER main contract
        want.safeApprove(address(EULER), type(uint256).max);
    }
    function revoke() external management {
        IERC20(address(eToken)).safeApprove(address(eStaking), 0); 
        // approve EULER main contract
        want.safeApprove(address(EULER), 0);
    }
}

