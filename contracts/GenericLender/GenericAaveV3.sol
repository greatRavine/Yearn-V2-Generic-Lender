// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../Interfaces/UniswapInterfaces/IUniswapV2Router02.sol";

import "./GenericLenderBase.sol";
import {IAToken} from "../Interfaces/Aave/V3/IAToken.sol";
import {IStakedAave} from "../Interfaces/Aave/V3/IStakedAave.sol";
import {IPool} from "../Interfaces/Aave/V3/IPool.sol";
import {IProtocolDataProvider} from "../Interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IRewardsController} from "../Interfaces/Aave/V3/IRewardsController.sol";
import {DataTypesV3} from "../Libraries/Aave/V3/DataTypesV3.sol";

//-- IReserveInterestRateStrategy implemented manually to avoid compiler errors for aprAfterDeposit function --//
/**
 * @title IReserveInterestRateStrategy
 * @author Aave
 * @notice Interface for the calculation of the interest rates
 */
interface IReserveInterestRateStrategy {
  /**
   * @notice Returns the base variable borrow rate
   * @return The base variable borrow rate, expressed in ray
   **/
  function getBaseVariableBorrowRate() external view returns (uint256);

  /**
   * @notice Returns the maximum variable borrow rate
   * @return The maximum variable borrow rate, expressed in ray
   **/
  function getMaxVariableBorrowRate() external view returns (uint256);

  /**
   * @notice Calculates the interest rates depending on the reserve's state and configurations
   * @param params The parameters needed to calculate interest rates
   * @return liquidityRate The liquidity rate expressed in rays
   * @return stableBorrowRate The stable borrow rate expressed in rays
   * @return variableBorrowRate The variable borrow rate expressed in rays
   **/
  function calculateInterestRates(DataTypesV3.CalculateInterestRatesParams calldata params)
    external
    view
    returns (
      uint256,
      uint256,
      uint256
    );
}

/********************
 *   A lender plugin for LenderYieldOptimiser for any erc20 asset on AaveV3
 *   Made by SamPriestley.com & jmonteer. Updated for V3 by Schlagatron
 *   https://github.com/Grandthrax/yearnV2-generic-lender-strat/blob/master/contracts/GenericLender/GenericAave.sol
 *
 ********************* */

contract GenericAaveV3 is GenericLenderBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    //Should be the same for all EVM chains
    IProtocolDataProvider public constant protocolDataProvider = IProtocolDataProvider(address(0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654));
    IAToken public aToken;
    
    //Only Applicable for Mainnet
    IStakedAave public constant stkAave = IStakedAave(0x4da27a545c0c5B758a6BA100e3a049001de870f5);

    address public keep3r;

    bool public isIncentivised;
    address[] public rewardTokens;
    uint256 public numberOfRewardTokens = 0;
    uint16 internal constant DEFAULT_REFERRAL = 179; // jmonteer's referral code
    uint16 internal customReferral;

    //These are currently set for Fantom WETH == WFTM
    address public constant WETH =
        address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);

    address public constant AAVE =
        address(0x6a07A792ab2965C72a5B8088d3a069A7aC3a993B);

    IUniswapV2Router02 public constant router =
        IUniswapV2Router02(address(0xF491e7B69E4244ad4002BC14e878a34207E38c29));

    uint256 constant internal SECONDS_IN_YEAR = 365 days;

    constructor(
        address _strategy,
        string memory name,
        IAToken _aToken,
        bool _isIncentivised
    ) public GenericLenderBase(_strategy, name) {
        _initialize(_aToken, _isIncentivised);
    }

    function initialize(IAToken _aToken, bool _isIncentivised) external {
        _initialize(_aToken, _isIncentivised);
    }

    function cloneAaveLender(
        address _strategy,
        string memory _name,
        IAToken _aToken,
        bool _isIncentivised
    ) external returns (address newLender) {
        newLender = _clone(_strategy, _name);
        GenericAaveV3(newLender).initialize(_aToken, _isIncentivised);
    }

    // for the management to activate / deactivate incentives functionality
    function setIsIncentivised(bool _isIncentivised) external management {
        // NOTE: if the aToken is not incentivised, getIncentivesController() might revert (aToken won't implement it)
        // to avoid calling it, we use the if else statement to update the rewards variables
        if(_isIncentivised) {
            address rewardController = address(aToken.getIncentivesController());
            require(rewardController != address(0), "!aToken does not have incentives controller set up");

            rewardTokens = IRewardsController(rewardController).getRewardsByAsset(address(want));
            numberOfRewardTokens = rewardTokens.length;

        } else {
            delete rewardTokens;
            numberOfRewardTokens = 0;
        }

        isIncentivised = _isIncentivised;
    }

    function setReferralCode(uint16 _customReferral) external management {
        require(_customReferral != 0, "!invalid referral code");
        customReferral = _customReferral;
    }

    function setKeep3r(address _keep3r) external management {
        keep3r = _keep3r;
    }

    function withdraw(uint256 amount) external override management returns (uint256) {
        return _withdraw(amount);
    }

    //emergency withdraw. sends balance plus amount to governance
    function emergencyWithdraw(uint256 amount) external override onlyGovernance {
        _lendingPool().withdraw(address(want), amount, address(this));

        want.safeTransfer(vault.governance(), want.balanceOf(address(this)));
    }

    function deposit() external override management {
        uint256 balance = want.balanceOf(address(this));
        _deposit(balance);
    }

    function withdrawAll() external override management returns (bool) {
        uint256 invested = _nav();
        uint256 returned = _withdraw(invested);
        return returned >= invested;
    }

    function startCooldown() external management {
        // for emergency cases
        IStakedAave(stkAave).cooldown(); // it will revert if balance of stkAave == 0
    }

    function nav() external view override returns (uint256) {
        return _nav();
    }

    function underlyingBalanceStored() public view returns (uint256 balance) {
        balance = aToken.balanceOf(address(this));
    }

    function apr() external view override returns (uint256) {
        return _apr();
    }

    function weightedApr() external view override returns (uint256) {
        uint256 a = _apr();
        return a.mul(_nav());
    }

    // calculates APR from Liquidity Mining Program
    function _incentivesRate(uint256 totalLiquidity, address rewardToken) public view returns (uint256) {
        // only returns != 0 if the incentives are in place at the moment.
        // it will fail if the isIncentivised is set to true but there is no incentives
        if(isIncentivised && block.timestamp < _incentivesController().getDistributionEnd(address(want), rewardToken)) {
            uint256 _emissionsPerSecond;
            (, _emissionsPerSecond, , ) = _incentivesController().getRewardsData(address(aToken), rewardToken);
            if(_emissionsPerSecond > 0) {
                uint256 emissionsInWant = _checkPrice(rewardToken, address(want), _emissionsPerSecond); // amount of emissions in want

                uint256 incentivesRate = emissionsInWant.mul(SECONDS_IN_YEAR).mul(1e18).div(totalLiquidity); // APRs are in 1e18

                return incentivesRate.mul(9_500).div(10_000); // 95% of estimated APR to avoid overestimations
            }
        }
        return 0;
    }

    function aprAfterDeposit(uint256 extraAmount) external view override returns (uint256) {
        //need to calculate new supplyRate after Deposit (when deposit has not been done yet)
        DataTypesV3.ReserveData memory reserveData = _lendingPool().getReserveData(address(want));

        (uint256 unbacked, , , uint256 totalStableDebt, uint256 totalVariableDebt, , , , uint256 averageStableBorrowRate, , , ) =
            protocolDataProvider.getReserveData(address(want));

        uint256 availableLiquidity = want.balanceOf(address(aToken));

        uint256 newLiquidity = availableLiquidity.add(extraAmount);

        (, , , , uint256 reserveFactor, , , , , ) = protocolDataProvider.getReserveConfigurationData(address(want));

        DataTypesV3.CalculateInterestRatesParams memory params = DataTypesV3.CalculateInterestRatesParams(
            unbacked,
            extraAmount,
            0,
            totalStableDebt,
            totalVariableDebt,
            averageStableBorrowRate,
            reserveFactor,
            address(want),
            address(aToken)
        );

        (uint256 newLiquidityRate, , ) = IReserveInterestRateStrategy(reserveData.interestRateStrategyAddress).calculateInterestRates(params);

        uint256 incentivesRate = 0;
        uint256 i = 0;
        //Passes the total Supply and the corresponding reward token address for each reward token the want has
        while(i < numberOfRewardTokens) {
            uint256 tokenIncentivesRate = _incentivesRate(newLiquidity.add(totalStableDebt).add(totalVariableDebt), rewardTokens[i]); 

            incentivesRate += tokenIncentivesRate;

            i ++;
        }
        return newLiquidityRate.div(1e9).add(incentivesRate); // divided by 1e9 to go from Ray to Wad
    }

    function hasAssets() external view override returns (bool) {
        return aToken.balanceOf(address(this)) > 0;
    }

    // Only for incentivised aTokens
    // this is a manual trigger to claim rewards
    // only callable if the token is incentivised by Aave Governance (rewardsTokens !=0)
    function harvest() external keepers{
        require(rewardTokens.length != 0, "No reward tokens");

        //claim all rewards
        address[] memory assets;
        assets[0] = address(aToken);
        (address[] memory rewardsList, uint256[] memory claimedAmounts) = 
            _incentivesController().claimAllRewardsToSelf(assets);
        
        //swap as much as possible back to want
        address token;
        for(uint256 i = 0; i < rewardsList.length; i ++) {
            token = rewardsList[i];
            if(token == address(stkAave)) {
                harvestStkAave();
            } else {
                _swapFrom(token, address(want), IERC20(token).balanceOf(address(this)));
            }
        }

        // deposit want in lending protocol
        uint256 balance = want.balanceOf(address(this));
        if(balance > 0) {
            _deposit(balance);
        }
    }

    function harvestStkAave() internal {
        if(!_checkCooldown()) {
            return;
        }

        uint256 stkAaveBalance = IERC20(address(stkAave)).balanceOf(address(this));
        if(stkAaveBalance > 0) {
            stkAave.redeem(address(this), stkAaveBalance);
        }

        // sell AAVE for want
        uint256 aaveBalance = IERC20(AAVE).balanceOf(address(this));
        _swapFrom(AAVE, address(want), aaveBalance);

        // request start of cooldown period
        if(IERC20(address(stkAave)).balanceOf(address(this)) > 0) {
            stkAave.cooldown();
        }
    }

    function harvestTrigger(uint256 callcost) external view returns (bool) {
        if(!isIncentivised) {
            return false;
        }

        address[] memory assets; 
        assets[0] = address(aToken);

        //check the total rewards available
        ( , uint256[] memory rewards) = 
            _incentivesController().getAllUserRewards(assets, address(this));

        // If we have a positive amount of any rewards return true
        for(uint256 i = 0; i < rewards.length; i ++) {
            if(rewards[i] > 0 ) {
                return true;
            }
        }

        //if we had no positive rewards return false
        return false;
    }

    function _initialize(IAToken _aToken, bool _isIncentivised) internal {
        require(address(aToken) == address(0), "GenericAave already initialized");

        if(_isIncentivised) {
            address rewardController = address(_aToken.getIncentivesController());
            require(rewardController != address(0), "!aToken does not have incentives controller set up");
            rewardTokens = IRewardsController(rewardController).getRewardsByAsset(address(want));
            numberOfRewardTokens = rewardTokens.length;
        }
        isIncentivised = _isIncentivised;

        aToken = _aToken;
        require(_lendingPool().getReserveData(address(want)).aTokenAddress == address(_aToken), "WRONG ATOKEN");
        IERC20(address(want)).safeApprove(address(_lendingPool()), type(uint256).max);
    }

    function _nav() internal view returns (uint256) {
        return want.balanceOf(address(this)).add(underlyingBalanceStored());
    }

    function _apr() internal view returns (uint256) {
        uint256 liquidityRate = uint256(_lendingPool().getReserveData(address(want)).currentLiquidityRate).div(1e9);// dividing by 1e9 to pass from ray to wad

        (, , , uint256 totalStableDebt, uint256 totalVariableDebt, , , , , , , ) =
            protocolDataProvider.getReserveData(address(want));

        uint256 availableLiquidity = want.balanceOf(address(aToken));

        uint256 incentivesRate = 0;
        uint256 i = 0;
        //Passes the total Supply and the corresponding reward token address for each reward token the want has
        while(i < numberOfRewardTokens) {
            uint256 tokenIncentivesRate = _incentivesRate(availableLiquidity.add(totalStableDebt).add(totalVariableDebt), rewardTokens[i]); 

            incentivesRate += tokenIncentivesRate;

            i ++;
        }

        return liquidityRate.add(incentivesRate);
    }

    //withdraw an amount including any want balance
    function _withdraw(uint256 amount) internal returns (uint256) {
        uint256 balanceUnderlying = aToken.balanceOf(address(this));
        uint256 looseBalance = want.balanceOf(address(this));
        uint256 total = balanceUnderlying.add(looseBalance);

        if (amount > total) {
            //cant withdraw more than we own
            amount = total;
        }

        if (looseBalance >= amount) {
            want.safeTransfer(address(strategy), amount);
            return amount;
        }

        //not state changing but OK because of previous call
        uint256 liquidity = want.balanceOf(address(aToken));

        if (liquidity > 1) {
            uint256 toWithdraw = amount.sub(looseBalance);

            if (toWithdraw <= liquidity) {
                //we can take all
                _lendingPool().withdraw(address(want), toWithdraw, address(this));
            } else {
                //take all we can
                _lendingPool().withdraw(address(want), liquidity, address(this));
            }
        }
        looseBalance = want.balanceOf(address(this));
        want.safeTransfer(address(strategy), looseBalance);
        return looseBalance;
    }

    function _deposit(uint256 amount) internal {
        IPool lp = _lendingPool();
        // NOTE: check if allowance is enough and acts accordingly
        // allowance might not be enough if
        //     i) initial allowance has been used (should take years)
        //     ii) lendingPool contract address has changed (Aave updated the contract address)
        if(want.allowance(address(this), address(lp)) < amount){
            IERC20(address(want)).safeApprove(address(lp), 0);
            IERC20(address(want)).safeApprove(address(lp), type(uint256).max);
        }

        uint16 referral;
        uint16 _customReferral = customReferral;
        if(_customReferral != 0) {
            referral = _customReferral;
        } else {
            referral = DEFAULT_REFERRAL;
        }

        lp.supply(address(want), amount, address(this), referral);
    }

    function _lendingPool() internal view returns (IPool lendingPool) {
        lendingPool = IPool(protocolDataProvider.ADDRESSES_PROVIDER().getPool());
    }

    function _checkCooldown() internal view returns (bool) {
        if(!isIncentivised) {
            return false;
        }

        uint256 cooldownStartTimestamp = IStakedAave(stkAave).stakersCooldowns(address(this));
        uint256 COOLDOWN_SECONDS = IStakedAave(stkAave).COOLDOWN_SECONDS();
        uint256 UNSTAKE_WINDOW = IStakedAave(stkAave).UNSTAKE_WINDOW();
        if(block.timestamp >= cooldownStartTimestamp.add(COOLDOWN_SECONDS)) {
            return block.timestamp.sub(cooldownStartTimestamp.add(COOLDOWN_SECONDS)) <= UNSTAKE_WINDOW || cooldownStartTimestamp == 0;
        } else {
            return false;
        }
    }

    function _checkPrice(
        address start,
        address end,
        uint256 _amount
    ) internal view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }

        uint256[] memory amounts = router.getAmountsOut(_amount, getTokenOutPath(start, end));

        return amounts[amounts.length - 1];
    }

    function _swapFrom(address _from, address _to, uint256 _amountIn) internal{
        if (_amountIn == 0) {
            return;
        }

        if(IERC20(_from).allowance(address(this), address(router)) < _amountIn) {
            IERC20(_from).safeApprove(address(router), 0);
            IERC20(_from).safeApprove(address(router), type(uint256).max);
        }

        router.swapExactTokensForTokens(
            _amountIn, 
            0, 
            getTokenOutPath(_from, _to), 
            address(this), 
            block.timestamp
        );
    }

    function getTokenOutPath(address _tokenIn, address _tokenOut) internal view returns (address[] memory _path) {
        bool isWeth = _tokenIn == WETH || _tokenOut == WETH;
        _path = new address[](isWeth ? 2 : 3);
        _path[0] = _tokenIn;

        if (isWeth) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = WETH;
            _path[2] = _tokenOut;
        }
    }

    function _incentivesController() internal view returns (IRewardsController) {
        if(isIncentivised) {
            return aToken.getIncentivesController();
        } else {
            return IRewardsController(0);
        }
    }

    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory protected = new address[](2);
        protected[0] = address(want);
        protected[1] = address(aToken);
        return protected;
    }

    modifier keepers() {
        require(
            msg.sender == address(keep3r) || msg.sender == address(strategy) || msg.sender == vault.governance() || msg.sender == IBaseStrategy(strategy).management(),
            "!keepers"
        );
        _;
    }
}
