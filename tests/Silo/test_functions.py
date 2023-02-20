from itertools import count
from brownie import Wei, reverts, ZERO_ADDRESS, interface, Contract
import brownie
from pytest import approx
from math import isclose
import random
from brownie.test import given, strategy


# test if staking apr calculation is correct
def test_mockapr(
    whale,
    gov,
    vault,
    strategy_test,
    currency,
    amount,
    GenericSiloTest,
    chain,
    strategist
):
    strategy = strategy_test    
    # plugin to check additional functions
    plugin = GenericSiloTest.at(strategy.lenders(0))
    depositAmount = plugin.valueInWant(plugin.liquidity())
    # sanity check on size:
    assert plugin.apr() == 0
    assert plugin.aprAfterDeposit(depositAmount) == 0
    plugin.setApr(20*10**18, {"from": gov})
    assert plugin.apr() == 20*10**18
    assert plugin.aprAfterDeposit(depositAmount//2) == 20*10**18
    assert plugin.aprAfterDeposit(2*depositAmount) == 0

# test if staking apr calculation is correct
def test_sellwantforxai(
    whale,
    gov,
    vault,
    strategy_test,
    currency,
    GenericSiloTest,
    xai,
    chain,
    strategist
):
    strategy = strategy_test    
    # plugin to check additional functions
    plugin = GenericSiloTest.at(strategy.lenders(0))
    decimals = currency.decimals()
    # 1000$ debt to pay
    debtinxai = 1000 * 10**18
    debtinwant = plugin.valueInWant(debtinxai)
    currency.transfer(plugin, debtinwant*2, {"from": whale})
    assert isclose(currency.balanceOf(plugin),2*debtinwant,rel_tol=1e-6)
    assert xai.balanceOf(plugin) == 0
    plugin.test_sellWantForXai(debtinxai,{"from": gov})
    assert isclose(xai.balanceOf(plugin),debtinxai, rel_tol=1e-6) and xai.balanceOf(plugin) >= debtinxai
    assert isclose(currency.balanceOf(plugin),debtinwant,rel_tol=1e-1)

# test if conversion calculations are correct
def test_conversion_calculations(
    strategy_test,
    currency,
    GenericSiloTest,
    valueOfCurrencyInDollars,
    price_provider,
    vault,
    xai
):
    strategy = strategy_test
    plugin = GenericSiloTest.at(strategy.lenders(0))

    # sanity test with configured prices
    # 1x
    estimatedValue = plugin.valueInXai(10**currency.decimals())
    assert isclose(valueOfCurrencyInDollars * 10**18, estimatedValue, rel_tol=0.1)
    estimatedWant = plugin.valueInWant(estimatedValue)
    assert isclose(10**currency.decimals(), estimatedWant, rel_tol=0.1)
    # 50x
    estimatedValue = plugin.valueInXai(50*10**currency.decimals())
    assert isclose(50* valueOfCurrencyInDollars * 10**18, estimatedValue, rel_tol=0.1)
    estimatedWant = plugin.valueInWant(estimatedValue)
    assert isclose(50*10**currency.decimals(), estimatedWant, rel_tol=0.1)
    # test if functions produce sensible output - should be inverse f(g(x)) = f(f^-1(x)) = x
    for i in range(10):
        # from xai to want and back
        value = random.randint(10**18, 10**22)
        assert isclose(plugin.valueInXai(plugin.valueInWant(value)),value, rel_tol=1e-3)
    for i in range(10):
        # from want to xai and back
        value = random.randint(10**currency.decimals(), 10**(currency.decimals()+4))
        assert isclose(plugin.valueInWant(plugin.valueInXai(value)),value, rel_tol=1e-3)


# test if staking apr calculation is correct
def test_deposit(
    chain,
    whale,
    gov,
    strategist,
    rando,
    vault,
    strategy_test,
    currency,
    amount,
    GenericSiloTest,
    xai_whale,
    xai_vault,
    lens,
    silo,
    xai
):
    # plugin to check additional functions
    strategy = strategy_test
    plugin = GenericSiloTest.at(strategy.lenders(0))
    decimals = currency.decimals()
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10000
    currency.approve(vault, 2**256 - 1, {"from": whale})
    currency.approve(vault, 2**256 - 1, {"from": strategist})
    depositAmount = amount//2
    assert plugin.hasAssets() == False
    # sanity check on size:
    form = "{:.2%}"
    formS = "{:,.0f}"
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})
    vault.deposit(depositAmount, {"from": whale})
    plugin.setApr(20*10**18, {"from": gov})
    assert plugin.hasAssets() == False
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist})
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist})
    assert plugin.hasAssets() == True
    assert isclose(plugin.nav(),depositAmount,rel_tol=10e-4, abs_tol=2)
    vault.deposit(depositAmount//10, {"from": strategist})
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist})
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist})
    assert isclose(plugin.nav(),depositAmount+depositAmount//10,rel_tol=10e-4, abs_tol=2)
    assert plugin.hasAssets() == True





