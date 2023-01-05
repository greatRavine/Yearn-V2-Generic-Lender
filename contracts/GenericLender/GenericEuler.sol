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
    IEulerEToken
} from "../Interfaces/Euler/IEuler.sol";
// import Euler Staking Interface (based on SNX staking)
import {
    IStakingRewards
} from "../Interfaces/Euler/IStakingRewards.sol";
import "../Interfaces/UniswapInterfaces/V3/ISwapRouter.sol";
import "../Interfaces/UniswapInterfaces/V3/IQuoterV2.sol";
import "./GenericLenderBase.sol";
contract GenericEuler is GenericLenderBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    // Mainnet - depending on WANT token!
    // "stakingRewards_eUSDC": "0xE5aFE81e63f0A52a3a03B922b30f73B8ce74D570",
    // "stakingRewards_eUSDT": "0x7882F919e3acCa984babd70529100F937d90F860",
    // "stakingRewards_eWETH": "0x229443bf7F1297192394B7127427DB172a5bDe9E"
    address public constant EULER = address(0x27182842E098f60e3D576794A5bFFb0777E025d3);
    IEulerMarkets public constant eMarkets = IEulerMarkets(address(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3));
    IEulerEToken public immutable eToken;
    IStakingRewards public immutable eStaking;

    //Uniswap pools & fees - if unused compiler just ignores...usually we only need EUL, WETH and want...
    IERC20 public constant WETH9 = IERC20(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IERC20 public constant USDC = IERC20(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    IERC20 public constant USDT = IERC20(address(0xdAC17F958D2ee523a2206206994597C13D831ec7));
    IERC20 public constant EUL = IERC20(address(0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b));
    IQuoterV2 public constant quoter = IQuoterV2(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter public constant uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);


    uint24 public constant poolFee030 = 3000;
    uint24 public constant poolFee005 = 500;
    uint24 public constant poolFee001 = 100;
    uint24 public constant poolFee100 = 10000;



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
        eToken = IEulerEToken(address(eMarkets.underlyingToEToken(vault.token())));
        IERC20(address(eToken)).approve(address(_stakingContract), type(uint).max);                    
        IERC20(address(vault.token())).approve(EULER, type(uint).max);
        IERC20(address(EUL)).approve(address(uniswapRouter), type(uint).max);
    }
}