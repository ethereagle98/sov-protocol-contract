from brownie import *

import time
import json

def main():
    thisNetwork = network.show_active()

    if thisNetwork == "development":
        acct = accounts[0]
        configFile =  open('./scripts/contractInteraction/testnet_contracts.json')
    elif thisNetwork == "testnet":
        acct = accounts.load("rskdeployer")
        configFile =  open('./scripts/contractInteraction/testnet_contracts.json')
    elif thisNetwork == "rsk-mainnet":
        acct = accounts.load("rskdeployer")
        configFile =  open('./scripts/contractInteraction/mainnet_contracts.json')
    else:
        raise Exception("network not supported")

    # load deployed contracts addresses
    contracts = json.load(configFile)
    protocolAddress = contracts['sovrynProtocol']
    if (thisNetwork == "testnet" or thisNetwork == "rsk-mainnet"):
        vestingOwner = contracts['multisig']
        cSOV1 = contracts['cSOV1']
        cSOV2 = contracts['cSOV2']
    else:
        vestingOwner = acct
        cSOV1 = acct.deploy(TestToken, "cSOV1", "cSOV1", 18, 1e26).address
        cSOV2 = acct.deploy(TestToken, "cSOV2", "cSOV2", 18, 1e26).address

    #deploy SOV
    SOVtoken = acct.deploy(SOV, 1e26)


    #deploy the staking contracts
    stakingLogic = acct.deploy(Staking)
    staking = acct.deploy(StakingProxy, SOVtoken.address)
    staking.setImplementation(stakingLogic.address)
    staking = Contract.from_abi("Staking", address=staking.address, abi=Staking.abi, owner=acct)

    #deploy fee sharing contract
    feeSharing = acct.deploy(FeeSharingProxy, protocolAddress, staking.address)

    # set fee sharing
    staking.setFeeSharing(feeSharing.address)


    #deploy VestingFactory
    vestingFactory = acct.deploy(VestingFactory)

    #deploy VestingRegistry
    vestingRegistry = acct.deploy(VestingRegistry, vestingFactory.address, SOVtoken.address, [cSOV1, cSOV2], staking.address, feeSharing.address, vestingOwner)
    vestingFactory.transferOwnership(vestingRegistry.address)

    DAY = 24 * 60 * 60
    FOUR_WEEKS = 4 * 7 * DAY

    # TeamVesting
    cliff = 6 * FOUR_WEEKS
    duration = 1092 * DAY
    teamVestingList = [
        [
            accounts[0],
            100000e18
        ],
        [
            accounts[1],
            200000e18
        ],
        [
            accounts[2],
            300000e18
        ],
        [
            accounts[3],
            400000e18
        ],
        [
            accounts[4],
            500000e18
        ]
    ]
    teamVestingAmount = 0
    for teamVesting in teamVestingList:
        amount = teamVesting[1]
        teamVestingAmount += amount
    print("Team Vesting Amount: ", teamVestingAmount)
    SOVtoken.transfer(vestingRegistry.address, teamVestingAmount)

    for teamVesting in teamVestingList:
        tokenOwner = teamVesting[0]
        amount = teamVesting[1]
        vestingRegistry.createTeamVesting(tokenOwner, amount, cliff, duration)
        vestingAddress = vestingRegistry.getTeamVesting(tokenOwner)
        vestingRegistry.stakeTokens(vestingAddress, amount)

        print("TeamVesting: ", vestingAddress)
        print(tokenOwner)
        print(amount)
        print(cliff)
        print(duration)


    # Vesting
    vestingList = [
        [
            accounts[0],
            100000e18,
            6 * FOUR_WEEKS,
            13 * FOUR_WEEKS
        ],
        [
            accounts[1],
            200000e18,
            7 * FOUR_WEEKS,
            14 * FOUR_WEEKS
        ],
        [
            accounts[2],
            300000e18,
            8 * FOUR_WEEKS,
            15 * FOUR_WEEKS
        ],
        [
            accounts[3],
            400000e18,
            9 * FOUR_WEEKS,
            16 * FOUR_WEEKS
        ],
        [
            accounts[4],
            500000e18,
            10 * FOUR_WEEKS,
            17 * FOUR_WEEKS
        ]
    ]
    vestingAmount = 0
    for vesting in vestingList:
        amount = vesting[1]
        vestingAmount += amount
    print("Vesting Amount: ", vestingAmount)
    SOVtoken.transfer(vestingRegistry.address, vestingAmount)

    for vesting in vestingList:
        tokenOwner = vesting[0]
        amount = vesting[1]
        cliff = vesting[2]
        duration = vesting[3]
        vestingRegistry.createVesting(tokenOwner, amount, cliff, duration)
        vestingAddress = vestingRegistry.getVesting(tokenOwner)
        vestingRegistry.stakeTokens(vestingAddress, amount)

        print("Vesting: ", vestingAddress)
        print(tokenOwner)
        print(amount)
        print(cliff)
        print(duration)


    # Development fund


    # Adoption fund


    # TODO Ecosystem fund, Programmatic sale
    # TODO move rest of the tokens
