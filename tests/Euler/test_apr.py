from itertools import count
from brownie import Wei, reverts, ZERO_ADDRESS, interface
import brownie




def test_staking_apr(
    chain,
    whale,
    gov,
    strategist,
    rando,
    vault,
    strategy,
    currency,
    amount,
    GenericEuler,
    staking_apy,
    staking_contract,
    reward_token
):
    # plugin to check additional functions
    plugin = GenericEuler.at(strategy.lenders(0))
    if (staking_contract is None):
        return

    want = interface.ERC20(currency)
    decimals = currency.decimals()
    currency.approve(vault, 2**256 - 1, {"from": whale})
    lens = interface.IEulerSimpleLens("0x5077B7642abF198b4a5b7C4BdCE4f03016C7089C")
    markets = interface.IEulerMarkets("0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3")
    etoken = interface.IEulerEToken(markets.underlyingToEToken(want.address))
    staking = interface.IStakingRewards(staking_contract)
    rewardsRate = staking.rewardRate()
    totalSupplyinWant = etoken.convertBalanceToUnderlying(staking.totalSupply())    
    (weiPerEul,_,_) = lens.getPriceFull(reward_token)
    (weiPerWant,_,_) = lens.getPriceFull(want.address)
    WantPerEul = weiPerEul/weiPerWant
    apr =  WantPerEul*rewardsRate/totalSupplyinWant*(60*60*24*365)*(10**decimals)/10**18
    
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10_000
    # sanity check on size:
    stakingApy = plugin._stakingApr(0)/10**18

    form = "{:.2%}"
    formS = "{:,.0f}"
    print(
        f"Off-chain calculated staking APR: {formS.format(apr)}"
        f"On-chain calculated staking APR: {formS.format(stakingApy)}"
    )

    # same as calculation in float
    assert stakingApy > apr * 0.99 and stakingApy < apr * 1.01
    # sanity on size .- assuming similar volume
    assert stakingApy > staking_apy * 0.2 and stakingApy < staking_apy * 5

def test_apr(
    chain,
    whale,
    gov,
    strategist,
    rando,
    vault,
    strategy,
    currency,
    amount,
    GenericEuler,
):
    # plugin to check additional functions
    plugin = GenericEuler.at(strategy.lenders(0))

    decimals = currency.decimals()
    currency.approve(vault, 2**256 - 1, {"from": whale})

    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10_000
    # sanity check before depositing
    assert plugin.apr() == plugin.aprAfterDeposit(0)
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})
    form = "{:.2%}"
    formS = "{:,.0f}"
    firstDeposit = amount
    predictedApr = strategy.estimatedFutureAPR(firstDeposit)
    tx = strategy.estimatedFutureAPR.transact(firstDeposit, {"from": gov})
    print(
        f"Predicted APR from {formS.format(firstDeposit/1e6)} deposit:"
        f" {form.format(predictedApr/1e18)}"
    )
    vault.deposit(firstDeposit, {"from": whale})
    print("Deposit: ", formS.format(firstDeposit / 1e6))
    chain.sleep(1)
    strategy.harvest({"from": strategist})
    realApr = strategy.estimatedAPR()
    print("Current APR: ", form.format(realApr / 1e18))
    status = strategy.lendStatuses()

    for j in status:
        print(
            f"Lender: {j[0]}, Deposits: {formS.format(j[1]/1e6)}, APR:"
            f" {form.format(j[2]/1e18)}"
        )

    assert realApr > predictedApr * 0.999 and realApr < predictedApr * 1.001

    predictedApr = strategy.estimatedFutureAPR(firstDeposit * 2)
    tx2 = strategy.estimatedFutureAPR.transact(firstDeposit * 2, {"from": gov})
    print(
        f"\nPredicted APR from {formS.format(firstDeposit/1e6)} deposit:"
        f" {form.format(predictedApr/1e18)}"
    )
    print("Deposit: ", formS.format(firstDeposit / 1e6))
    vault.deposit(firstDeposit, {"from": whale})

    chain.sleep(1)
    strategy.harvest({"from": strategist})
    realApr = strategy.estimatedAPR()

    print(f"Real APR after deposit: {form.format(realApr/1e18)}")
    status = strategy.lendStatuses()

    for j in status:
        print(
            f"Lender: {j[0]}, Deposits: {formS.format(j[1]/1e6)}, APR:"
            f" {form.format(j[2]/1e18)}"
        )
    assert realApr > predictedApr * 0.999 and realApr < predictedApr * 1.001


# plugin.withdrawAll()
# zeroApr =  plugin.apr()
# zeroFutureApr = plugin.aprAfterDeposit(0)
# assert zeroApr == zeroFutureApr

# irm = interface.IBaseIRM(plugin.eulerIRM())
# LENS = interface.IEulerSimpleLens("0x5077B7642abF198b4a5b7C4BdCE4f03016C7089C")
# (_,total,borrow,_)=LENS.getTotalSupplyAndDebts(vault.token())
# utilisation = (2**32-1)*borrow/total
# spy = irm.computeInterestRate(currency, utilisation)
# calculatedApr = plugin.computeAPYs(spy, borrow, total)
# assert calculatedApr == zeroApr
