import pytest
from brownie import Wei, config, Contract, interface


token_addresses = {
    "USDT": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
    "USDC": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    "WETH": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "YFI": "0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e",
    "LUSD": "0x5f98805a4e8be255a32880fdec7f6728c6568ba0",
    "RAI": "0x03ab458634910aad20ef5f1c8ee96f1d6ac54919"
}


# TODO: uncomment those tokens you want to test as want
@pytest.fixture(
    params=[
        "WETH",
        "USDC"
    ],
    scope="session",
    autouse=True,
)
def token(request):
    yield Contract(token_addresses[request.param])


@pytest.fixture
def currency(token):
    yield token


whale_addresses = {
    "USDT": "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
    "USDC": "0x0a59649758aa4d66e25f08dd01271e891fe52199",
    "WETH": "0x2f0b23f53734252bda2277357e97e1517d6b042a",
    "YFI": "0xfeb4acf3df3cdea7399794d0869ef76a6efaff52",
    "LUSD": "0x6f71fc3925605f06672409c71844ead4b700af5f",
    "RAI": "0x537037c5ae805b9d4cecab5ee07f12a8e59a15b2",
    "XAI": "0xc8cd77d4cd9511f2822f24ad14fe9e3c97c57836"
}

@pytest.fixture()
def weth_whale(accounts, token):
    yield accounts.at(whale_addresses["WETH"], force=True)

@pytest.fixture()
def xai_whale(accounts, token):
    yield accounts.at(whale_addresses["XAI"], force=True)

@pytest.fixture
def whale(accounts, token):
    acc = accounts.at(whale_addresses[token.symbol()], force=True)
    yield acc


token_prices = {
    "WETH": 1_600,
    "USDT": 1,
    "USDC": 1,
    "YFI": 6_500,
    "LUSD": 1,
    "RAI":2.8,
    "XAI": 1
}

@pytest.fixture(autouse=True)
def amount(token, whale):
    # this will get the number of tokens (around $1m worth of token)
    ten_million = round(10_000_000 / token_prices[token.symbol()])
    amount = ten_million * 10 ** token.decimals()
    # # In order to get some funds for the token you are about to use,
    # # it impersonate a whale address
    if 2*amount > token.balanceOf(whale):
        amount = token.balanceOf(whale)//2
    # token.transfer(user, amount, {"from": token_whale})
    yield amount

@pytest.fixture
def valueOfCurrencyInDollars(token):
    yield token_prices[token.symbol()]

@pytest.fixture(autouse=True)
def repository(interface):
    repo = interface.ISiloRepository("0xd998C35B7900b344bbBe6555cc11576942Cf309d")
    yield repo

@pytest.fixture(autouse=True)
def silo(interface, repository, currency, xai):
    if currency.symbol() == "WETH":
        silo = interface.ISilo(repository.getSilo(xai.address))  
    else:  
        silo = interface.ISilo(repository.getSilo(currency.address))
    yield silo


@pytest.fixture(autouse=True)
def lens(interface):
    lens = Contract.from_explorer("0xf12C3758c1eC393704f0Db8537ef7F57368D92Ea")
    yield lens

@pytest.fixture(autouse=True)
def strategist(accounts, whale, currency, amount):
    currency.transfer(accounts[1], amount / 10, {"from": whale})
    yield accounts[1]


@pytest.fixture(autouse=True)
def gov(accounts):
    yield accounts[3]


@pytest.fixture
def rewards(gov):
    yield gov  # TODO: Add rewards contract


@pytest.fixture
def guardian(accounts):
    # YFI Whale, probably
    yield accounts[2]


@pytest.fixture
def keeper(accounts):
    # This is our trusty bot!
    yield accounts[4]


@pytest.fixture
def rando(accounts):
    yield accounts[9]


@pytest.fixture
def trade_factory():
    yield Contract("0xd6a8ae62f4d593DAf72E2D7c9f7bDB89AB069F06")


@pytest.fixture
def gas_oracle():
    yield Contract("0xb5e1CAcB567d98faaDB60a1fD4820720141f064F")


@pytest.fixture
def strategist_ms(accounts):
    # like governance, but better
    yield accounts.at("0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7", force=True)


# specific token addresses
@pytest.fixture(autouse=True)
def weth(interface):
    yield interface.IERC20("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")

@pytest.fixture(autouse=True)
def xai(interface):
    yield interface.IERC20("0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc")


@pytest.fixture(scope="module", autouse=True)
def shared_setup(module_isolation):
    pass


@pytest.fixture()
def vault(gov, rewards, guardian, currency, pm):
    Vault = pm(config["dependencies"][0]).Vault
    vault = Vault.deploy({"from": guardian})
    vault.initialize(currency, gov, rewards, "", "")
    vault.setManagementFee(0, {"from": gov})
    yield vault


@pytest.fixture(autouse=True)
def xai_vault(gov, rewards, guardian, xai, pm):
    Vault = pm(config["dependencies"][0]).Vault
    xai_vault = Vault.deploy({"from": guardian})
    xai_vault.initialize(xai, gov, rewards, "", "")
    xai_vault.setManagementFee(0, {"from": gov})
    deposit_limit = 100_000_000 * (10**xai_vault.decimals())
    xai_vault.setDepositLimit(deposit_limit, {"from": gov})
    assert xai_vault.depositLimit() > 0
    yield xai_vault

@pytest.fixture(autouse=True)
def price_provider(interface):
    yield interface.IPriceProvidersRepository("0x7C2ca9D502f2409BeceAfa68E97a176Ff805029F")


@pytest.fixture()
def strategy(
    strategist,
    gov,
    rewards,
    keeper,
    vault,
    xai_vault,
    Strategy,
    GenericSiloTest
):
    strategy = strategist.deploy(Strategy, vault)
    strategy.setKeeper(keeper, {"from": gov})
    strategy.setWithdrawalThreshold(0, {"from": gov})
    strategy.setRewards(rewards, {"from": strategist})

    silo_plugin = strategist.deploy(GenericSiloTest, strategy, "GenericSilo", xai_vault.address)
    strategy.addLender(silo_plugin, {"from": gov})
    assert strategy.numLenders() == 1

    yield strategy