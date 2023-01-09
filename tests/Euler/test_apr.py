from itertools import count
from brownie import Wei, reverts, ZERO_ADDRESS
import brownie


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
