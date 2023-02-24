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
    GenericSilo,
    rando,
    vault,
    strategy,
    accounts,
    currency,
    xai_vault
):
    # Check original values
    plugin = GenericSilo.at(strategy.lenders(0))

    assert plugin.keeper() == ZERO_ADDRESS

    with brownie.reverts():
        plugin.setKeeper(accounts[1], {"from": rando})

    plugin.setKeeper(accounts[1], {"from": strategist})
    assert plugin.keeper() == accounts[1]
    
    tx = plugin.cloneSiloLender(
        strategy, "CloneGC", xai_vault.address,{"from": strategist}
    )
    clone = GenericSilo.at(tx.return_value)

    assert clone.keeper() == ZERO_ADDRESS

    with brownie.reverts():
        clone.setKeeper(accounts[1], {"from": rando})

    clone.setKeeper(accounts[1], {"from": strategist})
    assert clone.keeper() == accounts[1]
