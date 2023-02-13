from itertools import count
from brownie import Wei, reverts, ZERO_ADDRESS, interface
import brownie
from pytest import approx
from math import isclose
import random



# test if staking apr calculation is correct
def test_staking_apr(
    chain,
    whale,
    gov,
    strategist,
    rando,
    vault,
    strategy_test,
    currency,
    amount,
    GenericEulerTest,
    staking_apy,
    staking_contract,
    reward_token,
    lens,
    markets
):
    # plugin to check additional functions
    strategy = strategy_test
    plugin = GenericEulerTest.at(strategy.lenders(0))
    if (staking_contract is None):
        return

    decimals = currency.decimals()
    currency.approve(vault, 2**256 - 1, {"from": whale})
    etoken = interface.IEulerEToken(markets.underlyingToEToken(currency.address))
    staking = interface.IStakingRewards(staking_contract)
    rewardsRate = staking.rewardRate()
    totalSupplyinWant = etoken.convertBalanceToUnderlying(staking.totalSupply())    
    (weiPerEul,_,_) = lens.getPriceFull(reward_token.address)
    (weiPerWant,_,_) = lens.getPriceFull(currency.address)
    WantPerEul = weiPerEul/weiPerWant
    apr =  WantPerEul*rewardsRate/totalSupplyinWant*(60*60*24*365)*(10**decimals)/10**18
    
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10_000
    # sanity check on size:
    stakingApy = plugin.stakingApr(0)/10**18

    form = "{:.2%}"
    formS = "{:,.0f}"
    print(
        f"Off-chain calculated staking APR: {form.format(apr)}\n"
        f"On-chain calculated staking APR: {form.format(stakingApy)}\n"
    )

    # same as calculation in float
    assert stakingApy == approx(apr,rel=1e-3)
    # sanity on size .- assuming similar volume
    assert stakingApy > staking_apy * 0.2 and stakingApy < staking_apy * 5

# test if lending apr calculation is correct
def test_lending_apr(
    chain,
    whale,
    gov,
    strategist,
    rando,
    vault,
    strategy_test,
    currency,
    amount,
    GenericEulerTest
):
    # plugin to check additional functions
    strategy = strategy_test
    plugin = GenericEulerTest.at(strategy.lenders(0))
    form = "{:.2%}"
    formS = "{:,.0f}"
    depositAmount = amount//2
    decimals = currency.decimals()
    currency.approve(vault, 2**256 - 1, {"from": whale})
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10_000
    lens = interface.IEulerSimpleLens("0x5077B7642abF198b4a5b7C4BdCE4f03016C7089C")
    # in RAY 1e27
    (_,_,supplyAPY) = lens.interestRates(currency.address)
    # in 1e18 -> scale up
    estimatedSupplyAPY = plugin.lendingApr(0)*1e9
    assert estimatedSupplyAPY == approx(supplyAPY, rel=1e-3)
    print(
        f"Contract calculated lending APR: {form.format(estimatedSupplyAPY/1e27)}\n"
        f"Lens calculated lending APR: {form.format(supplyAPY/1e27)}\n"
        f"Before depositing: {formS.format(depositAmount/ 10**decimals)}\n"
    )
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})
    estimatedSupplyAPY = plugin.lendingApr(depositAmount)*1e9
    vault.deposit(depositAmount, {"from": whale})
    print("Deposit: ", formS.format(depositAmount / 10**decimals))
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist}) 
    (_,lent,staked,_)=plugin.getBalance()
    assert isclose(lent + staked,depositAmount, abs_tol=1)
    (_,_,supplyAPY) = lens.interestRates(currency.address)
    assert estimatedSupplyAPY == approx(supplyAPY, rel=1e-3)
    print(
        f"Contract calculated lending APR: {form.format(estimatedSupplyAPY/1e27)}\n"
        f"Lens calculated lending APR: {form.format(supplyAPY/1e27)}\n"
        f"After depositing: {formS.format(depositAmount/ 10**decimals)}\n"
    )


# test if deposit function works correctly
# tests 0 deposit
# tests if deposit moves all into staking or lending (depending whether staking is enabled)
# tests if balances are correct if staking is disabled when already deposited and if deposit afterwards only go into lending
def test_plugin_deposit(
    chain,
    whale,
    gov,
    strategist,
    vault,
    strategy,
    currency,
    amount,
    GenericEuler
):
    # plugin to check additional functions
    plugin = GenericEuler.at(strategy.lenders(0))
    form = "{:.2%}"
    formS = "{:,.0f}"
    depositAmount = amount//2
    decimals = currency.decimals()
    currency.approve(vault, 2**256 - 1, {"from": whale})
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10_000
    waitBlock = 25
    nav = plugin.nav({"from": strategist})
    assert nav == 0
    # deposit 0
    plugin.deposit({"from": strategist})
    nav = plugin.nav({"from": strategist})
    (local,lent,staked,_) = plugin.getBalance()
    assert local == 0 and lent == 0 and staked == 0
    currency.transfer(plugin.address, depositAmount, {"from": whale})
    (local,lent,staked,_) = plugin.getBalance()
    assert isclose(depositAmount, local, abs_tol=2) and lent == 0 and staked == 0
    print(
        f"Transfering {formS.format(depositAmount/10**decimals)} into lender plugin\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    plugin.deposit({"from": strategist})
    (local,lent,staked,_) = plugin.getBalance()
    if plugin.hasStaking():
        assert lent == 0 and isclose(staked,depositAmount, rel_tol=1e-6)
    else:
        assert staked == 0 and isclose(lent,depositAmount, rel_tol=1e-6)
    print(
        f"Depositing {formS.format(depositAmount/10**decimals)} into Euler\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    if plugin.hasStaking():
        plugin.deactivateStaking({"from": gov})
        (local,lent,staked,_) = plugin.getBalance()
        assert staked == 0 and isclose(lent,depositAmount, rel_tol=1e-6)
        assert plugin.hasStaking() == False
        print(
            f"After deactivating Staking\n"
            f"local: {formS.format(local/10**decimals)}\n"
            f"lent: {formS.format(lent/10**decimals)}\n"
            f"staked: {formS.format(staked/10**decimals)}\n"
        )
        currency.transfer(plugin.address, depositAmount, {"from": whale})
        (local,lent,staked,_) = plugin.getBalance()
        assert isclose(depositAmount, local, abs_tol=2) and isclose(depositAmount, lent, abs_tol=2) and staked == 0
        print(
            f"Transfering another {formS.format(depositAmount/10**decimals)} into lender plugin\n"
            f"local: {formS.format(local/10**decimals)}\n"
            f"lent: {formS.format(lent/10**decimals)}\n"
            f"staked: {formS.format(staked/10**decimals)}\n"
        )
        plugin.deposit({"from": strategist})
        (local,lent,staked,_) = plugin.getBalance()
        assert staked == 0 and isclose(lent,2*depositAmount, rel_tol=1e-6)
        print(
            f"Depositing another {formS.format(depositAmount/10**decimals)} into Euler\n"
            f"local: {formS.format(local/10**decimals)}\n"
            f"lent: {formS.format(lent/10**decimals)}\n"
            f"staked: {formS.format(staked/10**decimals)}\n"
        )




# tests 0 withdrawal
# tests higher than balance withdrawal
# tests repeated regular withdrawals
# tests withdrawAll functionality
def test_plugin_withdrawal(
    chain,
    whale,
    gov,
    strategist,
    vault,
    strategy,
    currency,
    amount,
    GenericEuler,
    euler_lending_pool
):
    plugin = GenericEuler.at(strategy.lenders(0))
    form = "{:.2%}"
    formS = "{:,.0f}"
    depositAmount = amount//2
    decimals = currency.decimals()
    currency.approve(vault, 2**256 - 1, {"from": whale})
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10_000
    waitBlock = 25
    nav = plugin.nav({"from": strategist})
    assert nav == 0
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})
    vault.deposit(depositAmount, {"from": whale})
    print("Deposit: ", formS.format(depositAmount / 10**decimals))
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist}) 
    (local,lent,staked,_) = plugin.getBalance()
    assert (isclose(depositAmount, lent, abs_tol=2) or isclose(depositAmount, staked, abs_tol=2)) and local == 0
    print(
        f"After Vault deposit of {formS.format(depositAmount/10**decimals)} into strategy\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    print(f"\n----wait {waitBlock} blocks----")
    chain.mine(waitBlock)
    chain.sleep(waitBlock * 13)
    withdraw_return = plugin.withdraw(0).return_value
    assert withdraw_return == 0
    (local,lent,staked,total) = plugin.getBalance()
    print(
        f"After depositing {formS.format(depositAmount/10**decimals)} and waiting a couple of blocks\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    withdraw_return = plugin.withdraw(total*2).return_value
    assert isclose(withdraw_return, total, rel_tol=1e-3,abs_tol=2)
    (local,lent,staked,total) = plugin.getBalance()
    print(
        f"After too high withdrawal we reported {formS.format(withdraw_return/10**decimals)}\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    assert isclose(total,0,abs_tol=2)
    print(f"\n----wait {waitBlock} blocks----")
    chain.mine(waitBlock)
    chain.sleep(waitBlock * 13)
    strategy.harvest({"from": strategist})  
    (local,lent,staked,total) = plugin.getBalance()
    assert (isclose(withdraw_return, lent, rel_tol=1e-2, abs_tol=2) or isclose(withdraw_return, staked, abs_tol=2)) and local == 0
    print(
        f"Harvest to redeposit {formS.format(withdraw_return/10**decimals)}\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    for i in range(3):
        (_,_,_,oldtotal) = plugin.getBalance()
        towithdraw = random.randint(1,int(total//2))
        withdraw_return = plugin.withdraw(towithdraw,{"from": strategist}).return_value
        (local,lent,staked,total) = plugin.getBalance()
        assert isclose(oldtotal - withdraw_return, total, rel_tol=1e-5, abs_tol=2) and oldtotal > total
        print(
            f"After trying to withdraw {formS.format(towithdraw/10**decimals)}\n"
            f"local: {formS.format(local/10**decimals)}\n"
            f"lent: {formS.format(lent/10**decimals)}\n"
            f"staked: {formS.format(staked/10**decimals)}\n"
        )
        print(f"\n----wait {waitBlock} blocks----")
        chain.mine(waitBlock)
        chain.sleep(waitBlock * 13)
    withdraw_success = plugin.withdrawAll({"from": strategist}).return_value
    (local,lent,staked,total) = plugin.getBalance()
    assert total == 0 and withdraw_success==True


# tests withdrawal with limitied liquidity
def test_plugin_withdrawal_with_limited_liquidity(
    chain,
    whale,
    gov,
    strategist,
    vault,
    strategy,
    currency,
    amount,
    GenericEuler,
    euler_lending_pool,
    accounts,
    dtoken,
    wethetoken,
    weth_whale,
    weth,
    markets
):
    if currency.symbol() == "WETH":
        return
    plugin = GenericEuler.at(strategy.lenders(0))
    form = "{:.2%}"
    formS = "{:,.0f}"
    depositAmount = amount//2
    decimals = currency.decimals()
    currency.approve(vault, 2**256 - 1, {"from": whale})
    weth.approve(euler_lending_pool, 2**256 - 1, {"from": weth_whale})
    wethetoken.deposit(0, 300000 * 10**18, {'from': weth_whale})
    markets.enterMarket(0,weth.address,{'from': weth_whale})
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10_000
    waitBlock = 25
    nav = plugin.nav({"from": strategist})
    assert nav == 0
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})
    vault.deposit(depositAmount, {"from": whale})
    print("Deposit: ", formS.format(depositAmount / 10**decimals))
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist}) 
    (local,lent,staked,oldtotal) = plugin.getBalance()
    before_strategy_balance = currency.balanceOf(strategy)
    print(
        f"Harvest to deposit {formS.format(oldtotal/10**decimals)}\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
        f"strategy: {formS.format(before_strategy_balance/10**decimals)}\n"
    )
    # pool_account = accounts.at(euler_lending_pool, force=True)
    pool_balance = currency.balanceOf(euler_lending_pool)
    remaining_liquidity = oldtotal//5
    # currency.transfer(gov, pool_balance - remaining_liquidity, {"from": pool_account})
    dtoken.borrow(0,pool_balance - remaining_liquidity,{'from': weth_whale})
    withdraw_return = plugin.withdraw(2*remaining_liquidity).return_value
    assert isclose(withdraw_return, remaining_liquidity, rel_tol=1e-3,abs_tol=2)
    (local,lent,staked,total) = plugin.getBalance()
    after_strategy_balance = currency.balanceOf(strategy)
    print(
        f"After withdrawal of {formS.format(2*remaining_liquidity/10**decimals)} without enough liquidity - only {formS.format(remaining_liquidity/10**decimals)} liquidity\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
        f"strategy: {formS.format(after_strategy_balance/10**decimals)}\n"
    )
    assert isclose(before_strategy_balance + oldtotal, after_strategy_balance + total, rel_tol=1e-4,abs_tol=10)
    assert isclose(oldtotal, total + withdraw_return,rel_tol=1e-3,abs_tol=2)


# tests withdrawAll functionality with limitied liquidity
def test_plugin_withdrawal_all_with_limited_liquidity(
    chain,
    whale,
    gov,
    strategist,
    vault,
    strategy,
    currency,
    amount,
    GenericEuler,
    euler_lending_pool,
    accounts,
    dtoken,
    wethetoken,
    weth_whale,
    weth,
    markets
):
    if currency.symbol() == "WETH":
        return
    plugin = GenericEuler.at(strategy.lenders(0))
    form = "{:.2%}"
    formS = "{:,.0f}"
    depositAmount = amount//2
    decimals = currency.decimals()
    currency.approve(vault, 2**256 - 1, {"from": whale})
    weth.approve(euler_lending_pool, 2**256 - 1, {"from": weth_whale})
    wethetoken.deposit(0, 300000 * 10**18, {'from': weth_whale})
    markets.enterMarket(0,weth.address,{'from': weth_whale})
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10_000
    waitBlock = 25
    nav = plugin.nav({"from": strategist})
    assert nav == 0
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})
    vault.deposit(depositAmount, {"from": whale})
    print("Deposit: ", formS.format(depositAmount / 10**decimals))
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist}) 
    (local,lent,staked,oldtotal) = plugin.getBalance()
    print(
        f"Harvest to deposit {formS.format(oldtotal/10**decimals)}\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    pool_account = accounts.at(euler_lending_pool, force=True)
    pool_balance = currency.balanceOf(euler_lending_pool)
    strategy_balance = currency.balanceOf(strategy)
    remaining_liquidity = oldtotal//5
    dtoken.borrow(0,pool_balance - remaining_liquidity,{'from': weth_whale})
    withdraw_return = plugin.withdrawAll().return_value
    assert withdraw_return==False
    (local,lent,staked,total) = plugin.getBalance()
    print(
        f"After withdrawal without enough liquidity {formS.format(withdraw_return/10**decimals)}\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    assert isclose(oldtotal, total + remaining_liquidity,rel_tol=1e-3,abs_tol=2)
    assert withdraw_return == False
    assert isclose(strategy_balance, currency.balanceOf(strategy) - remaining_liquidity, rel_tol=1e-4,abs_tol=2)

# tests emergencyWithdrawal functionality
# tests emergencyWithdrawal functionality with limitied liquidity
def test_plugin_emergency_withdrawal_with_limited_liquidity(
    chain,
    whale,
    gov,
    strategist,
    vault,
    strategy,
    currency,
    amount,
    GenericEuler,
    euler_lending_pool,
    accounts,
    dtoken,
    wethetoken,
    weth_whale,
    weth,
    markets
):
    if currency.symbol() == "WETH":
        return
    plugin = GenericEuler.at(strategy.lenders(0))
    form = "{:.2%}"
    formS = "{:,.0f}"
    depositAmount = amount//2
    decimals = currency.decimals()
    currency.approve(vault, 2**256 - 1, {"from": whale})
    weth.approve(euler_lending_pool, 2**256 - 1, {"from": weth_whale})
    wethetoken.deposit(0, 300000 * 10**18, {'from': weth_whale})
    markets.enterMarket(0,weth.address,{'from': weth_whale})
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10_000
    waitBlock = 25
    nav = plugin.nav({"from": strategist})
    assert nav == 0
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})
    vault.deposit(depositAmount, {"from": whale})
    print("Deposit: ", formS.format(depositAmount / 10**decimals))
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist}) 
    (local,lent,staked,oldtotal) = plugin.getBalance()
    print(
        f"Harvest to deposit {formS.format(oldtotal/10**decimals)}\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    pool_account = accounts.at(euler_lending_pool, force=True)
    pool_balance = currency.balanceOf(euler_lending_pool)
    before_gov_balance = currency.balanceOf(gov)
    remaining_liquidity = oldtotal//5
    dtoken.borrow(0,pool_balance - remaining_liquidity,{'from': weth_whale})
    plugin.emergencyWithdraw(oldtotal//2)
    after_gov_balance = currency.balanceOf(gov)
    assert isclose(after_gov_balance - before_gov_balance, remaining_liquidity, rel_tol=1e-3,abs_tol=2)
    (local,lent,staked,total) = plugin.getBalance()
    print(
        f"After emergencyWithdrawal without enough liquidity {formS.format(oldtotal//2/10**decimals)}\n"
        f"local: {formS.format(local/10**decimals)}\n"
        f"lent: {formS.format(lent/10**decimals)}\n"
        f"staked: {formS.format(staked/10**decimals)}\n"
    )
    assert isclose(oldtotal, total + remaining_liquidity,rel_tol=1e-3,abs_tol=2)



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
