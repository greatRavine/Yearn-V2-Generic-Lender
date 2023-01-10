import pytest
from brownie import Wei, config, Contract


token_addresses = {
    "USDT": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
    "USDC": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    "WETH": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
}


# TODO: uncomment those tokens you want to test as want
@pytest.fixture(
    params=[
        "USDC",
        "USDT",
        "WETH",
    ],
    scope="session",
    autouse=True,
)
def token(request):
    yield Contract(token_addresses[request.param])


@pytest.fixture
def currency(token):
    yield token


stakingContract_addresses = {
    "WETH": "0x229443bf7F1297192394B7127427DB172a5bDe9E",  # eWETH
    "USDT": "0x7882F919e3acCa984babd70529100F937d90F860",  # eUSDT
    "USDC": "0xE5aFE81e63f0A52a3a03B922b30f73B8ce74D570",  # eUSDC
}


@pytest.fixture
def staking_contract(token):
    yield stakingContract_addresses[token.symbol()]


whale_addresses = {
    "USDT": "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
    "USDC": "0x0a59649758aa4d66e25f08dd01271e891fe52199",
    "WETH": "0x2f0b23f53734252bda2277357e97e1517d6b042a",
}


@pytest.fixture
def whale(accounts, token):
    acc = accounts.at(whale_addresses[token.symbol()], force=True)
    yield acc


token_prices = {
    "WETH": 1_200,
    "USDT": 1,
    "USDC": 1,
}


@pytest.fixture(autouse=True)
def amount(token, whale):
    # this will get the number of tokens (around $1m worth of token)
    ten_million = round(10_000_000 / token_prices[token.symbol()])
    amount = ten_million * 10 ** token.decimals()
    # # In order to get some funds for the token you are about to use,
    # # it impersonate a whale address
    if amount > token.balanceOf(whale):
        amount = token.balanceOf(whale)
    # token.transfer(user, amount, {"from": token_whale})
    yield amount


@pytest.fixture
def valueOfCurrencyInDollars(token):
    yield token_prices[token.symbol()]


@pytest.fixture
def eul_whale(accounts):
    yield accounts.at("0x27182842E098f60e3D576794A5bFFb0777E025d3", force=True)

@pytest.fixture
def euler_lending_pool():
    yield "0x27182842E098f60e3D576794A5bFFb0777E025d3"




@pytest.fixture()
def strategist(accounts, whale, currency, amount):
    currency.transfer(accounts[1], amount / 10, {"from": whale})
    yield accounts[1]


@pytest.fixture
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
@pytest.fixture
def weth(interface):
    yield interface.IERC20("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")


@pytest.fixture
def eul(interface):
    token_address = "0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b"
    yield interface.IERC20(token_address)


@pytest.fixture(scope="module", autouse=True)
def shared_setup(module_isolation):
    pass


@pytest.fixture
def vault(gov, rewards, guardian, currency, pm):
    Vault = pm(config["dependencies"][0]).Vault
    vault = Vault.deploy({"from": guardian})
    vault.initialize(currency, gov, rewards, "", "")
    vault.setManagementFee(0, {"from": gov})
    yield vault


@pytest.fixture
def strategy(
    strategist,
    gov,
    rewards,
    keeper,
    vault,
    Strategy,
    staking_contract,
    GenericEuler
):
    strategy = strategist.deploy(Strategy, vault)
    strategy.setKeeper(keeper, {"from": gov})
    strategy.setWithdrawalThreshold(0, {"from": gov})
    strategy.setRewards(rewards, {"from": strategist})

    euler_plugin = strategist.deploy(GenericEuler, strategy, "GenericEulerLendnStake", staking_contract)

    strategy.addLender(euler_plugin, {"from": gov})
    assert strategy.numLenders() == 1

    yield strategy