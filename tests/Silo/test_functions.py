from itertools import count
from brownie import Wei, reverts, ZERO_ADDRESS, interface, Contract
import brownie
from pytest import approx
from math import isclose
import random
from brownie.test import given, strategy




# def test_tend(
#     chain,
#     whale,
#     gov,
#     strategist,
#     strategist_ms,
#     vault,
#     strategy_test,
#     currency,
#     amount,
#     GenericSiloTest,
#     gas_oracle,
#     xai,
#     xai_strategy,
#     xai_whale,
#     xai_vault
# ):
#     # plugin to check additional functions
#     strategy = strategy_test
#     gas_oracle.setMaxAcceptableBaseFee(10000 * 1e9, {"from": strategist_ms})
#     plugin = GenericSiloTest.at(strategy.lenders(0))
#     decimals = currency.decimals()
#     deposit_limit = 100_000_000 * (10**decimals)
#     debt_ratio = 10000
#     currency.approve(vault, 2**256 - 1, {"from": whale})
#     currency.approve(vault, 2**256 - 1, {"from": strategist})
#     depositAmount = amount//10
#     assert plugin.hasAssets() == False
#     vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
#     vault.setDepositLimit(deposit_limit, {"from": gov})
#     vault.deposit(depositAmount, {"from": whale})
#     chain.sleep(1)
#     chain.mine(1)
#     strategy.harvest({"from": strategist})
#     chain.mine(1)
#     chain.sleep(1)
#     dust = plugin.dust()
#     while (plugin.tendTrigger(0) == False):
#         #make the xai vault profitable
#         xaimount = min(plugin.valueInXai(depositAmount), xai.balanceOf(xai_whale)/5)
#         xai.transfer(xai_strategy, xaimount, {"from": xai_whale})
#         chain.mine(1)
#         chain.sleep(1)
#         xai_vault.report(xaimount,0,0, {'from': xai_strategy})
#         chain.mine(random.randint(1,50))
#         chain.sleep(random.randint(24*3600,7*24*3600))
#         xai_strategy.harvest({"from": strategist})
#         print("-----------------")
#         print("Xai in Xai Vault:", plugin.balanceOfXaiVaultInXai()/10**18)
#         print("Debt :", plugin.balanceOfDebt()/10**18)
#         print("Price per Share in Xai Vault:", xai_vault.pricePerShare())
#         print("Surplus: ",(plugin.balanceOfXaiVaultInXai() - plugin.balanceOfDebt())/10**18)
#         print("Delta in Debt: ", (plugin.test_deltaInDebt())/10**18)
#         print("Debt Ratio: ", (plugin.test_getCurrentLTV()/10**18))
#         print("-----------------") 
#     assert(plugin.tendTrigger(0) == True)
#     assert(plugin.test_deltaInDebt()/10**18 > 0)
#     plugin.tend({"from": strategist})
#     assert(isclose(plugin.test_deltaInDebt()/10**18,0,abs_tol=10**16))
#     assert(plugin.tendTrigger(0) == False)


def test_getsurplus(
    chain,
    whale,
    gov,
    strategist,
    vault,
    strategy_test,
    currency,
    amount,
    GenericSiloTest,
    silo,
    xai,
    xai_strategy,
    xai_whale,
    xai_vault
):
    # plugin to check additional functions
    strategy = strategy_test
    plugin = GenericSiloTest.at(strategy.lenders(0))
    decimals = currency.decimals()
    deposit_limit = 100_000_000 * (10**decimals)
    debt_ratio = 10000
    currency.approve(vault, 2**256 - 1, {"from": whale})
    currency.approve(vault, 2**256 - 1, {"from": strategist})
    depositAmount = amount//10
    assert plugin.hasAssets() == False
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})
    vault.deposit(depositAmount, {"from": whale})
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist})
    chain.mine(1)
    chain.sleep(1)
    dust = plugin.dust()
    while ((plugin.balanceOfXaiVaultInXai() - plugin.balanceOfDebt()) < (dust + plugin.test_deltaInDebt())):
        #make the xai vault profitable
        xaimount = min(plugin.valueInXai(depositAmount), xai.balanceOf(xai_whale)/5)
        xai.transfer(xai_strategy, xaimount, {"from": xai_whale})
        chain.mine(1)
        chain.sleep(1)
        xai_vault.report(xaimount,0,0, {'from': xai_strategy})
        chain.mine(1)
        chain.sleep(1)
        xai_strategy.harvest({"from": strategist})
        print("-----------------")
        print("Xai in Xai Vault:", plugin.balanceOfXaiVaultInXai()/10**18)
        print("Debt :", plugin.balanceOfDebt()/10**18)
        print("Price per Share in Xai Vault:", xai_vault.pricePerShare())
        print("Surplus: ",(plugin.balanceOfXaiVaultInXai() - plugin.balanceOfDebt())/10**18)
        print("Threshold: ", (dust + plugin.test_deltaInDebt())/10**18)
        print("-----------------") 
    assert((plugin.balanceOfXaiVaultInXai() - plugin.balanceOfDebt()) > (dust + plugin.test_deltaInDebt()))
    assert(plugin.balanceOfWant() == 0)
    plugin.test_getSurplus(dust)
    assert(isclose(plugin.balanceOfWant(),plugin.valueInWant(dust), rel_tol=0.1))       


def test_unwind(
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
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})
    vault.deposit(depositAmount, {"from": whale})
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist})
    col =  plugin.balanceOfCollateral()
    debt = plugin.balanceOfDebt()
    bf = plugin.borrowFactor()
    print("Delta: ", plugin.test_deltaInDebt())
    delta = plugin.test_deltaInDebt()
    print ("collateral: ", col)
    print ("debt: ", debt)
    testamount = depositAmount//20
    plugin.test_unwind(testamount, {"from": strategist})
    col_after =  plugin.balanceOfCollateral()
    debt_after = plugin.balanceOfDebt()
    bf = plugin.realBorrowFactor()
    print ("collateral_a: ", col_after)
    print ("debt_a: ", debt_after)
    assert isclose(col-col_after, testamount, rel_tol=0.01)
    assert isclose(debt-debt_after, plugin.valueInXai(testamount*bf//10**18), rel_tol=0.05)
    chain.sleep(100)
    chain.mine(1)
    col =  plugin.balanceOfCollateral()
    debt = plugin.balanceOfDebt()
    bf = plugin.borrowFactor()
    print ("collateral: ", col)
    print ("debt: ", debt)
    testamount = depositAmount//2

    plugin.test_unwind(testamount, {"from": strategist})
    col_after =  plugin.balanceOfCollateral()
    debt_after = plugin.balanceOfDebt()
    bf = plugin.realBorrowFactor()
    print ("collateral_a: ", col_after)
    print ("debt_a: ", debt_after)
    assert isclose(col-col_after, testamount, rel_tol=0.01)
    assert isclose(debt-debt_after, plugin.valueInXai(testamount)*bf/10**18, rel_tol=0.05)

# test if staking apr calculation is correct
def test_deltas(
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
    chain.sleep(1)
    chain.mine(1)
    strategy.harvest({"from": strategist})
    while (plugin.test_deltaInCollateral()== 0):
        chain.sleep(3600)
        chain.mine(10)
    delta1 = plugin.test_deltaInCollateral()
    collateral = plugin.balanceOfCollateral()
    debt = plugin.balanceOfDebt()
    borrowfactor = plugin.borrowFactor() / 10**18
    delta2 = plugin.test_deltaInDebt()
    assert isclose(plugin.valueInWant(debt) / borrowfactor,collateral + delta1,rel_tol=1e-3)
    print ("Collateral Delta: " ,delta1)
    print ("Debt Delta: " ,delta2)
    assert isclose(plugin.valueInXai(collateral * borrowfactor),debt - delta2,rel_tol=1e-3)





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

def test_sellxaiforwant(
    whale,
    gov,
    vault,
    strategy_test,
    currency,
    GenericSiloTest,
    xai,
    xai_whale,
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
    xai.transfer(plugin, debtinxai*2, {"from": xai_whale})
    assert isclose(xai.balanceOf(plugin),2*debtinxai,rel_tol=1e-6)
    assert currency.balanceOf(plugin) == 0
    plugin.test_sellXaiForWant(debtinxai,{"from": gov})
    assert isclose(currency.balanceOf(plugin),debtinwant, rel_tol=1e-2)
    assert isclose(xai.balanceOf(plugin),debtinxai,rel_tol=1e-2)


def test_collateral_n_debt_calculations(
    whale,
    gov,
    vault,
    strategy_test,
    currency,
    GenericSiloTest,
    xai,
    xai_whale,
    chain,
    strategist
):
    strategy = strategy_test    
    # plugin to check additional functions
    plugin = GenericSiloTest.at(strategy.lenders(0))
    decimals = currency.decimals()
    bf = plugin.borrowFactor()/10**18
    rbf = plugin.realBorrowFactor()/10**18
    print("Borrow Factor: ", bf)
    print("Real Borrow Factor: ", rbf)
    print("Currency: ", currency.symbol())
    testamount = random.randint(1, 10) * (10**decimals)
    debt_from_testamount = plugin.test_calcCorrespondingDebt(testamount)
    testamountinxai = plugin.valueInXai(testamount)
    assert(isclose(debt_from_testamount, testamountinxai*bf, rel_tol=1e-3))
    testxaiamount = random.randint(1000, 10000) * (10**decimals)
    collateral_from_testxaiamount = plugin.test_calcCorrespondingCollateral(testxaiamount)
    testxaiamountincurrency = plugin.valueInWant(testxaiamount)
    assert(isclose(collateral_from_testxaiamount, testxaiamountincurrency/bf, rel_tol=1e-3))
    
