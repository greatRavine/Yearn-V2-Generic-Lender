from itertools import count
from brownie import Wei, reverts, Contract, interface, ZERO_ADDRESS
from useful_methods import genericStateOfVault, genericStateOfStrat
import random
import brownie
import pytest
from weiroll import WeirollPlanner, WeirollContract
from math import isclose

def test_trade_factory(
    chain,
    whale,
    gov,
    strategist,
    rando,
    vault,
    strategy,
    trade_factory,
    interface,
    weth,
    currency,
    eul_whale,
    gas_oracle,
    strategist_ms,
    GenericEuler,
    reward_token,
    staking_contract
):
    
    starting_balance = currency.balanceOf(strategist)
    decimals = currency.decimals()
    plugin = GenericEuler.at(strategy.lenders(0))
    if not plugin.hasStaking():
        return
    gas_oracle.setMaxAcceptableBaseFee(10000 * 1e9, {"from": strategist_ms})

    currency.approve(vault, 2**256 - 1, {"from": whale})
    currency.approve(vault, 2**256 - 1, {"from": strategist})

    deposit_limit = 1_000_000_000 * (10 ** (decimals))
    debt_ratio = 10_000
    vault.addStrategy(strategy, debt_ratio, 0, 2**256 - 1, 500, {"from": gov})
    vault.setDepositLimit(deposit_limit, {"from": gov})

    assert deposit_limit == vault.depositLimit()
    # our humble strategist deposits some test funds
    depositAmount = 501 * (10 ** (decimals))
    vault.deposit(depositAmount, {"from": whale})

    assert strategy.estimatedTotalAssets() == 0
    chain.mine(1)
    assert strategy.harvestTrigger(1) == True

    chain.sleep(1)
    strategy.harvest({"from": strategist})
    # accrue some rewards...
    chain.sleep(1000)
    chain.mine(1000)
    estaking = interface.IStakingRewards(staking_contract)
    earned = estaking.earned(plugin.address)
    plugin.setDust(2*earned, {"from": gov})
    assert plugin.dust() == 2*earned
    assert plugin.harvestTrigger(10) == False
    plugin.setDust(earned, {"from": gov})
    assert plugin.dust() == earned
    chain.sleep(1)
    chain.mine(1)
    assert plugin.harvestTrigger(10) == True
    plugin.harvest({"from": gov})
    assert estaking.earned(plugin.address) == 0
    balance = reward_token.balanceOf(plugin.address)
    assert isclose(balance,earned, rel_tol=1e-2)

    # send some eul to the strategy to trade the shit out of it :)
    toSend = 200 * 10**reward_token.decimals()
    reward_token.transfer(plugin.address, toSend, {"from": eul_whale})
    assert reward_token.balanceOf(plugin.address) >= toSend
    navBefore = plugin.nav()
    currencyBefore = currency.balanceOf(plugin)

    with reverts():
        plugin.setTradeFactory(trade_factory.address, {"from": rando})

    assert plugin.tradeFactory() == ZERO_ADDRESS
    plugin.setTradeFactory(trade_factory.address, {"from": gov})
    assert plugin.tradeFactory() == trade_factory.address

    # nothing should have been sold because ySwap is set and not yet executed
    assert reward_token.balanceOf(plugin.address) >= toSend
    token_in = reward_token
    token_out = currency

    print(f"Executing trade...")
    receiver = plugin.address
    amount_in = token_in.balanceOf(plugin.address)
    assert amount_in > 0

    router = WeirollContract.createContract(
        Contract("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D")
    )
    receiver = plugin

    planner = WeirollPlanner(trade_factory)
    token_in = WeirollContract.createContract(token_in)

    route = []
    if currency.symbol() == "WETH":
        route = [token_in.address, currency.address]
    else:
        route = [token_in.address, weth.address, currency.address]

    planner.add(
        token_in.transferFrom(
            plugin.address,
            trade_factory.address,
            amount_in,
        )
    )

    planner.add(token_in.approve(router.address, amount_in))

    planner.add(
        router.swapExactTokensForTokens(
            amount_in, 0, route, receiver.address, 2**256 - 1
        )
    )

    cmds, state = planner.plan()
    trade_factory.execute(cmds, state, {"from": trade_factory.governance()})
    afterBal = token_out.balanceOf(plugin)
    print(token_out.balanceOf(plugin))

    assert afterBal > 0
    assert reward_token.balanceOf(plugin.address) == 0

    # must have more want tokens after the ySwap is executed
    assert plugin.nav() > navBefore
    assert currency.balanceOf(plugin) > currencyBefore

    plugin.removeTradeFactoryPermissions({"from": strategist})
    assert plugin.tradeFactory() == ZERO_ADDRESS
    assert reward_token.allowance(plugin.address, trade_factory.address) == 0
 

