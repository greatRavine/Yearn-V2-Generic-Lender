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
        "USDC",
        "USDT",
        "WETH",
        "YFI",
        "LUSD",
        "RAI"
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
    if token.symbol() in stakingContract_addresses:
        yield stakingContract_addresses[token.symbol()]
    else:
        yield None



stakingApy = {
    "WETH": 0.0171,  # eWETH
    "USDT": 0.0201,  # eUSDT
    "USDC": 0.0219,  # eUSDC
}


@pytest.fixture
def staking_apy(token):
    if token.symbol() in stakingApy:
        yield stakingApy[token.symbol()]
    else:
        yield None

whale_addresses = {
    "USDT": "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
    "USDC": "0x0a59649758aa4d66e25f08dd01271e891fe52199",
    "WETH": "0x2f0b23f53734252bda2277357e97e1517d6b042a",
    "YFI": "0xfeb4acf3df3cdea7399794d0869ef76a6efaff52",
    "LUSD": "0x6f71fc3925605f06672409c71844ead4b700af5f",
    "RAI": "0x537037c5ae805b9d4cecab5ee07f12a8e59a15b2"
}



@pytest.fixture
def weth_whale(accounts, token):
    yield accounts.at("0x2f0b23f53734252bda2277357e97e1517d6b042a", force=True)

@pytest.fixture
def whale(accounts, token):
    acc = accounts.at(whale_addresses[token.symbol()], force=True)
    yield acc


token_prices = {
    "WETH": 1_200,
    "USDT": 1,
    "USDC": 1,
    "YFI": 6_500,
    "LUSD": 1,
    "RAI":2.8
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


@pytest.fixture
def eul_whale(accounts):
    yield accounts.at("0x27182842E098f60e3D576794A5bFFb0777E025d3", force=True)

@pytest.fixture
def euler_lending_pool():
    yield "0x27182842E098f60e3D576794A5bFFb0777E025d3"


@pytest.fixture()
def markets(interface):
    markets = interface.IEulerMarkets("0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3")
    yield markets

@pytest.fixture()
def lens(interface):
    lens = interface.IEulerSimpleLens("0x5077B7642abF198b4a5b7C4BdCE4f03016C7089C")
    yield lens

@pytest.fixture()
def etoken(currency, markets, interface):
    etoken = interface.IEulerEToken(markets.underlyingToEToken(currency.address))
    yield etoken

@pytest.fixture()
def dtoken(currency, markets, interface):
    dtoken = interface.IEulerDToken(markets.underlyingToDToken(currency.address))
    yield dtoken
    
@pytest.fixture()
def wethetoken(markets, interface):
    etoken = interface.IEulerEToken(markets.underlyingToEToken("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"))
    yield etoken

@pytest.fixture()
def wethdtoken(markets, interface):
    dtoken = interface.IEulerDToken(markets.underlyingToDToken("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"))
    yield dtoken

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
def reward_token(interface):
    token_address = "0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b"
    yield interface.ERC20(token_address)


@pytest.fixture
def reward_token():
    yield "0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b"



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

    euler_plugin = strategist.deploy(GenericEuler, strategy, "GenericEulerLendnStake")
    assert euler_plugin.hasStaking() == False 
    if staking_contract is not None:
        euler_plugin.activateStaking(staking_contract,2*1e20,{"from": strategist})
        assert euler_plugin.hasStaking() == True
    strategy.addLender(euler_plugin, {"from": gov})
    assert strategy.numLenders() == 1

    yield strategy