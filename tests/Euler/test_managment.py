from itertools import count
from brownie import Wei, reverts, ZERO_ADDRESS
import brownie


def test_manual_override(
    strategy,
    chain,
    vault,
    currency,
    interface,
    whale,
    strategist,
    gov,
    rando,
    amount,
):

    decimals = currency.decimals()

    deposit_limit = 100_000_000 * (10**decimals)
    vault.addStrategy(strategy, 9800, 0, 2**256 - 1, 500, {"from": gov})

    currency.approve(vault, 2**256 - 1, {"from": whale})
    currency.approve(vault, 2**256 - 1, {"from": strategist})

    vault.setDepositLimit(deposit_limit, {"from": gov})
    assert vault.depositLimit() > 0

    amount1 = amount / 1000
    amount2 = amount / 10
    vault.deposit(amount1, {"from": strategist})
    vault.deposit(amount2, {"from": whale})

    chain.sleep(1)
    strategy.harvest({"from": strategist})

    status = strategy.lendStatuses()

    for j in status:
        plugin = interface.IGeneric(j[3])

        with brownie.reverts("!management"):
            plugin.emergencyWithdraw(1, {"from": rando})
        with brownie.reverts("!management"):
            plugin.withdrawAll({"from": rando})
        with brownie.reverts("!management"):
            plugin.deposit({"from": rando})
        with brownie.reverts("!management"):
            plugin.withdraw(1, {"from": rando})


def test_setter_functions(
    chain,
    whale,
    gov,
    strategist,
    GenericEuler,
    rando,
    vault,
    strategy,
    accounts,
    staking_contract,
    currency,
):
    # Check original values
    plugin = GenericEuler.at(strategy.lenders(0))

    assert plugin.keep3r() == ZERO_ADDRESS

    with brownie.reverts():
        plugin.setKeep3r(accounts[1], {"from": rando})

    plugin.setKeep3r(accounts[1], {"from": strategist})
    assert plugin.keep3r() == accounts[1]

    if plugin.hasStaking():
        assert plugin.minEarnedToClaim() > 0
        newThreshold = 3 * 1e20
        plugin.setRewardThreshold(newThreshold, {"from": strategist})
        assert plugin.minEarnedToClaim() == newThreshold
        plugin.deactivateStaking({"from": strategist})
        assert plugin.hasStaking() == False 
    
    tx = plugin.cloneEulerLender(
        strategy, "CloneGC", {"from": strategist}
    )
    clone = GenericEuler.at(tx.return_value)

    assert clone.keep3r() == ZERO_ADDRESS

    with brownie.reverts():
        clone.setKeep3r(accounts[1], {"from": rando})

    assert clone.hasStaking() == False 

    clone.setKeep3r(accounts[1], {"from": strategist})
    assert clone.keep3r() == accounts[1]
