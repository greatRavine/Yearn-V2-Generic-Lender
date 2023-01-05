from functools import partialmethod
from pathlib import Path
from pdb import pm
import yaml
import click
import os
from brownie import interface, config, accounts, Contract, project, network, web3, FlashloanAPR
from eth_utils import is_checksum_address



def main():
    acct = accounts[0]
    fl = FlashloanAPR.deploy({"from": acct})
    aToken = "0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811"
    underlying = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
    weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    flashlender = interface.IERC3156FlashLender(fl._lender())
    amount= 100000*10**6
    tx = fl.testFlashBorrow(fl._lender(), fl.address, underlying, aToken, 1000*10**6)
    print(f"APR after depositing { amount }: {fl.apr()/10**27}")
