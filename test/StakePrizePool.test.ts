import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { Contract, ContractFactory } from "ethers"

const { deployMockContract } = require('ethereum-waffle')

const { ethers } = require('ethers')
const { expect } = require('chai')
const hardhat = require('hardhat')

const toWei = ethers.utils.parseEther

const debug = require('debug')('ptv3:PrizePool.test')

let overrides = { gasLimit: 9500000 }

describe('StakePrizePool', function() {
  let wallet: SignerWithAddress
  let wallet2: SignerWithAddress

  let prizePool: Contract
  let erc20token: Contract
  let erc721token: Contract
  let stakeToken: Contract
  let registry: Contract

  let poolMaxExitFee = toWei('0.5')

  let ticket: Contract

  let StakePrizePool: ContractFactory

  let initializeTxPromise
  let isInitializeTest = false

  const initializeStakePrizePool = async (stakeTokenAddress: string) => {
    return await prizePool['initialize(address,address[],uint256,address)'](
      registry.address,
      [ticket.address],
      poolMaxExitFee,
      stakeTokenAddress,
    );
  }

  beforeEach(async () => {
    [wallet, wallet2] = await hardhat.ethers.getSigners()
    debug(`using wallet ${wallet.address}`)

    debug('mocking tokens...')
    const IERC20 = await hardhat.artifacts.readArtifact("IERC20Upgradeable")
    erc20token = await deployMockContract(wallet, IERC20.abi, overrides)

    const IERC721 = await hardhat.artifacts.readArtifact("IERC721Upgradeable")
    erc721token = await deployMockContract(wallet, IERC721.abi, overrides)

    const ERC20Mintable = await hardhat.ethers.getContractFactory("ERC20Mintable")
    stakeToken = await ERC20Mintable.deploy("name", "SSYMBOL")

    const RegistryInterface = await hardhat.artifacts.readArtifact("RegistryInterface")
    registry = await deployMockContract(wallet, RegistryInterface.abi, overrides)

    debug('deploying StakePrizePool...')
    StakePrizePool = await hardhat.ethers.getContractFactory("StakePrizePool", wallet, overrides)

    prizePool = await StakePrizePool.deploy()

    const Ticket = await hardhat.ethers.getContractFactory("Ticket")
    ticket = await Ticket.deploy()
    await ticket.initialize("name", "SYMBOL", 18, prizePool.address)
    initializeTxPromise = await initializeStakePrizePool(stakeToken.address)
  })

  describe('initialize()', () => {
    
    beforeEach(async () => {
      prizePool = await StakePrizePool.deploy()
    })

    it('should initialize StakePrizePool', async () => {
      initializeTxPromise = await initializeStakePrizePool(stakeToken.address)

      await expect(initializeTxPromise)
        .to.emit(prizePool, 'StakePrizePoolInitialized')
        .withArgs(
          stakeToken.address
        )
    })

    it('should fail to initialize StakePrizePool if stakeToken is address zero', async () => {
      await expect(
        initializeStakePrizePool(ethers.constants.AddressZero),
      ).to.be.revertedWith('StakePrizePool/stake-token-not-zero-address')
    })
  })

  describe('_redeem()', () => {
    it('should return amount staked', async () => {
      await stakeToken.approve(prizePool.address, toWei('100'))
      await stakeToken.mint(wallet.address, toWei('100'))
      await prizePool.depositTo(wallet.address, toWei('100'), ticket.address, ethers.constants.AddressZero)
      await prizePool.withdrawInstantlyFrom(wallet.address, toWei('100'), ticket.address, toWei('100'))
    })
  })

  describe('canAwardExternal()', () => {
    it('should not allow the stake award', async () => {
      expect(await prizePool.canAwardExternal(stakeToken.address)).to.be.false
    })
  })

  describe('balance()', () => {
    it('should return the staked balance', async () => {
      await stakeToken.approve(prizePool.address, toWei('100'))
      await stakeToken.mint(wallet.address, toWei('100'))
      await prizePool.depositTo(wallet.address, toWei('100'), ticket.address, ethers.constants.AddressZero)
      expect(await prizePool.callStatic.balance()).to.equal(toWei('100'))
    })
  })

  describe('_token()', () => {
    it('should return the staked token token', async () => {
      expect(await prizePool.token()).to.equal(stakeToken.address)
    })
  })
});
