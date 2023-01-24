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
import "../Interfaces/Euler/RPow.sol";
import "./GenericLenderBase.sol";
import {ITradeFactory} from "../Interfaces/ySwaps/ITradeFactory.sol";
import {ISilo} from "../Interfaces/Silo/ISilo.sol";
import {ISiloRepository} from "../Interfaces/Silo/ISiloRepository.sol";

contract GenericSilo is GenericLenderBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;



    // Constants 
    uint256 internal constant SECONDS_PER_YEAR = 365.2425 * 86400;
    IERC20 public constant XAI = IERC20(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc);
    ISiloRepository public constant silorepository = ISiloRepository(0xd998C35B7900b344bbBe6555cc11576942Cf309d);
    address public constant silolens = address(0xf12C3758c1eC393704f0Db8537ef7F57368D92Ea);




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
        string memory name
    ) public GenericLenderBase(_strategy, name) {
        _initialize();
    }
    function initialize() external {
        _initialize();
    }
    function _initialize() internal {

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



    // not used with claim rewards - only used for harvest with harvest trigger!
    // to be removed if harvest & harvest trigger are not used 
    function setRewardThreshold(uint256  _minEarnedToClaim) external management{
        minEarnedToClaim = _minEarnedToClaim;
    }

    // borrowed from spalen0
    // https://github.com/spalen0/Yearn-V2-Generic-Lender/blob/c29eace1bf4a0b58d424b860eb6a605341507177/contracts/GenericLender/GenericAaveMorpho.sol#L92
    function cloneSiloLender(
        address _strategy,
        string memory _name
    ) external returns (address newLender) {
        newLender = _clone(_strategy, _name);
        GenericSilo(newLender).initialize();
    }

    function setKeep3r(address _keep3r) external management {
        keep3r = _keep3r;
    }

    //return current holdings
    function nav() external view override returns (uint256) {
        return _nav();
    }

    function _nav() internal view returns (uint256) {
        (,uint256 total) = getBalance();
        return total;
    }
    function getBalance() public view returns (uint256, uint256) {
        uint256 local = want.balanceOf(address(this));

        return (local,0);
    }

    function apr() external view override returns (uint256) {
        return _apr();
    }

    // scaled by 1e18
    function _apr() internal view returns (uint256) {
        // Only supply APY - staking not included - haven't found a clean way to get staking apr
        // RAY(1e27)
        return 0;
    }

    function aprAfterDeposit(uint256 _amount) external view override  returns (uint256) {
        return 0;
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




    // claim Staking rewards via trade handler
    function claimRewards() external keepers {
        _claimRewards();
    }

    function _claimRewards() internal {

    }      




    // Alternative with harvest triggers

    // function harvest() external keepers {
    //     _claimRewards();
    // }

    // function harvestTrigger(uint256 /*callCost*/) external view returns(bool) {
    //     if(!hasStaking) return false;
    //     if(eStaking.earned(address(this)) > _minEarnedToClaim) return true;
    // }





    function _withdraw(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        uint256 local = want.balanceOf(address(this));
        want.safeTransfer(address(strategy), local); 
        return local;
        
    }

    function deposit() external override management {
        //deposit

    }


    function emergencyWithdraw(uint256 _amount) external override management {
        //withdraw
        want.safeTransfer(vault.governance(), want.balanceOf(address(this)));
    }

    function withdrawAll() external override management returns (bool) {

        uint256 looseBalance = want.balanceOf(address(this));
        want.safeTransfer(address(strategy), looseBalance);
        (uint256 alocal,uint256 atotal) = getBalance();
        return(atotal == 0);
    }

    function hasAssets() external view override returns (bool) {
        (,uint256 total) = getBalance();
        return (total > 0);
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


// internal functions
// 

    function _depositSilo() {
        local = want.balanceOf(address(this));
        silo.deposit(address(want), local, true);
    }

    function _withdrawSilo(_amount) {
        if (_amount == 0){
            return;
        }
        silo.withdaw(address(want), _amount, true);
    }


   // ---------------------- YSWAPS FUNCTIONS ----------------------
    // function setTradeFactory(address _tradeFactory) external onlyGovernance {
    //     if (tradeFactory != address(0)) {
    //         _removeTradeFactoryPermissions();
    //     }

    //     ITradeFactory tf = ITradeFactory(_tradeFactory);

    //     IERC20(EUL).safeApprove(_tradeFactory, type(uint256).max);
    //     tf.enable(address(EUL), address(want));
        
    //     tradeFactory = _tradeFactory;
    // }

    // function removeTradeFactoryPermissions() external management {
    //     _removeTradeFactoryPermissions();
    // }

    // function _removeTradeFactoryPermissions() internal {
    //     IERC20(EUL).safeApprove(tradeFactory, 0);
        
    //     tradeFactory = address(0);
    // }

}

