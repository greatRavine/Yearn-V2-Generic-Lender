from itertools import count
from brownie import Wei, reverts
from useful_methods import genericStateOfStrat, genericStateOfVault, deposit, sleep
import random
import brownie
from math import isclose


# this test cycles through every plugin and checks we can add/remove lender and withdraw
def test_withdrawals_work(
    interface,
    chain,
    whale,
    gov,
    strategist,
    vault,
    strategy,
    currency,
    valueOfCurrencyInDollars,
    GenericSilo,
    amount,
    lens,
    xai,
    xai_strategy,
    xai_whale,
    xai_vault
):
    starting_balance = currency.balanceOf(strategist)
    decimals = currency.decimals()

    currency.approve(vault, 2**256 - 1, {"from": whale})
    currency.approve(vault, 2**256 - 1, {"from": strategist})

    deposit_limit = 1_000_000_000 * 10**decimals
    debt_ratio = 10000
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})

    status = strategy.lendStatuses()
    depositAmount = amount / 100
    vault.deposit(depositAmount, {"from": strategist})
    assert(isclose(currency.balanceOf(vault),depositAmount,abs_tol=1,rel_tol=1e-6))

    # whale deposits as well
    whale_deposit = amount / 2
    vault.deposit(whale_deposit, {"from": whale})
    assert(isclose(currency.balanceOf(vault),depositAmount + whale_deposit,abs_tol=1,rel_tol=1e-6))
    chain.sleep(1)
    strategy.harvest({"from": strategist})
    sleep(chain, 25)
    strategy.harvest({"from": strategist})

    # TODO: remove all lenders -> to withdraw all amounts
    # Test that we can remove the lender. If we have more debt than xai in the vault, we can't remove the lender
    plugin = GenericSilo.at(strategy.lenders(0))
    assert plugin.balanceOfDebt() > plugin.balanceOfXaiVaultInXai()
        # we are in debt!
    with brownie.reverts():
        strategy.safeRemoveLender(plugin, {"from": gov})
    #make the xai vault profitable
    xaimount = xai_vault.totalAssets()//5
    xai.transfer(xai_strategy, xaimount, {"from": xai_whale})
    xai_vault.report(xaimount,0,0, {'from': xai_strategy})
    chain.mine(1)
    chain.sleep(1)
    xai_strategy.harvest({"from": strategist})         
    tx = strategy.safeRemoveLender(plugin, {"from": gov})
    assert currency.balanceOf(plugin) == 0
    assert currency.balanceOf(strategy) > (depositAmount + whale_deposit) * 0.999

    form = "{:.2%}"
    formS = "{:,.0f}"

   
    # print("Testing ", j[0])
    strategy.addLender(plugin, {"from": gov})
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert plugin.nav() > (depositAmount + whale_deposit) * 0.999

    shareprice = vault.pricePerShare()

    shares = vault.balanceOf(strategist)
    expectedout = shares * shareprice / 10**decimals
    balanceBefore = currency.balanceOf(strategist)
    # print(f"Lender: {j[0]}, Deposits: {formS.format(plugin.nav()/1e6)}")

    vault.withdraw(vault.balanceOf(strategist), {"from": strategist})
    balanceAfter = currency.balanceOf(strategist)
    # print(f"after Lender: {j[0]}, Deposits: {formS.format(plugin.nav()/1e6)}")

    withdrawn = balanceAfter - balanceBefore
    assert withdrawn > expectedout * 0.99 and withdrawn < expectedout * 1.01

    shareprice = vault.pricePerShare()

    shares = vault.balanceOf(whale)
    expectedout = shares * shareprice / 10**decimals
    balanceBefore = currency.balanceOf(whale)
    vault.withdraw(vault.balanceOf(whale), {"from": whale})
    balanceAfter = currency.balanceOf(whale)

    withdrawn = balanceAfter - balanceBefore
    assert withdrawn > expectedout * 0.99 and withdrawn < expectedout * 1.01

 
    vault.deposit(whale_deposit, {"from": whale})
    vault.deposit(depositAmount, {"from": strategist})
    strategy.harvest({"from": strategist})
    assert plugin.balanceOfDebt() > plugin.balanceOfXaiVaultInXai()
    currency.transfer(plugin, plugin.valueInWant(plugin.balanceOfDebt()-plugin.balanceOfXaiVaultInXai()) , {"from": whale})
    strategy.safeRemoveLender(plugin)
    # verify plugin is empty or just have less than a penny
    assert plugin.nav() < (valueOfCurrencyInDollars / 100) * 10**decimals
    assert isclose(currency.balanceOf(strategy),(depositAmount + whale_deposit),rel_tol=1e-2)

    shareprice = vault.pricePerShare()

    shares = vault.balanceOf(strategist)
    expectedout = shares * shareprice / 10**decimals
    balanceBefore = currency.balanceOf(strategist)

    # genericStateOfStrat(strategy, currency, vault)
    # genericStateOfVault(vault, currency)

    vault.withdraw(vault.balanceOf(strategist), {"from": strategist})
    balanceAfter = currency.balanceOf(strategist)

    # genericStateOfStrat(strategy, currency, vault)
    # genericStateOfVault(vault, currency)

    chain.mine(1)
    withdrawn = balanceAfter - balanceBefore
    assert withdrawn > expectedout * 0.99 and withdrawn < expectedout * 1.01

    shareprice = vault.pricePerShare()
    shares = vault.balanceOf(whale)
    expectedout = shares * shareprice / 10**decimals

    balanceBefore = currency.balanceOf(whale)
    vault.withdraw(vault.balanceOf(whale), {"from": whale})
    balanceAfter = currency.balanceOf(whale)
    withdrawn = balanceAfter - balanceBefore
    assert withdrawn > expectedout * 0.99 and withdrawn < expectedout * 1.01
