import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { Contract, ContractFactory } from "ethers"

const { deployMockContract } = require('ethereum-waffle')
const { ethers } = require('ethers')
const { expect } = require('chai')
const hardhat = require('hardhat')

const toWei = ethers.utils.parseEther

const debug = require('debug')('ptv3:YieldSourcePrizePool.test')

let overrides = { gasLimit: 9500000 }

describe('YieldSourcePrizePool', function() {
  let wallet: SignerWithAddress
  let wallet2: SignerWithAddress

  let prizePool: Contract
  let depositToken: Contract
  let reserveRegistry: Contract
  let yieldSource: Contract
  let ticket: Contract
  let YieldSourcePrizePool: ContractFactory

  let poolMaxExitFee = toWei('0.5')

  let initializeTxPromise: Promise<any>

  beforeEach(async () => {
    [wallet, wallet2] = await hardhat.ethers.getSigners()
    debug(`using wallet ${wallet.address}`)

    debug('creating token...')
    const ERC20MintableContract =  await hardhat.ethers.getContractFactory("ERC20Mintable", wallet, overrides)
    depositToken = await ERC20MintableContract.deploy("Token", "TOKE")

    debug('creating yield source mock...')
    const IYieldSource = await hardhat.artifacts.readArtifact("IYieldSource")
    yieldSource =  await deployMockContract(wallet, IYieldSource.abi, overrides)
    yieldSource.mock.depositToken.returns(depositToken.address)

    const RegistryInterface = await hardhat.artifacts.readArtifact("RegistryInterface")
    reserveRegistry = await deployMockContract(wallet, RegistryInterface.abi, overrides)

    debug('deploying YieldSourcePrizePool...')
    YieldSourcePrizePool =  await hardhat.ethers.getContractFactory("YieldSourcePrizePool", wallet, overrides)
    prizePool = await YieldSourcePrizePool.deploy()

    const Ticket = await hardhat.ethers.getContractFactory("Ticket")
    ticket = await Ticket.deploy()
    await ticket.initialize("name", "SYMBOL", 18, prizePool.address)

    initializeTxPromise = prizePool.initializeYieldSourcePrizePool(
      reserveRegistry.address,
      [ticket.address],
      poolMaxExitFee,
      yieldSource.address
    )

    await initializeTxPromise

    await prizePool.setPrizeStrategy(wallet2.address)
  })

  describe('initialize()', () => {
    it('should initialize correctly', async () => {
      await expect(initializeTxPromise)
        .to.emit(prizePool, 'YieldSourcePrizePoolInitialized')
        .withArgs(
          yieldSource.address
        )

      expect(await prizePool.yieldSource()).to.equal(yieldSource.address)
    })

    it('should require the yield source', async () => {
      prizePool = await YieldSourcePrizePool.deploy()

      await expect(prizePool.initializeYieldSourcePrizePool(
        reserveRegistry.address,
        [ticket.address],
        poolMaxExitFee,
        ethers.constants.AddressZero
      )).to.be.revertedWith("YieldSourcePrizePool/yield-source-not-contract-address")
    })

    it('should require a valid yield source', async () => {
      prizePool = await YieldSourcePrizePool.deploy()

      await expect(prizePool.initializeYieldSourcePrizePool(
        reserveRegistry.address,
        [ticket.address],
        poolMaxExitFee,
        prizePool.address
      )).to.be.revertedWith("YieldSourcePrizePool/invalid-yield-source")
    })
  })

  describe('supply()', async () => {
    it('should supply assets to the yield source', async () => {
      await yieldSource.mock.supplyTokenTo.withArgs(toWei('10'), prizePool.address).returns()

      await depositToken.approve(prizePool.address, toWei('10'))
      await depositToken.mint(wallet.address, toWei('10'))
      await prizePool.depositTo(wallet.address, toWei('10'), ticket.address, ethers.constants.AddressZero)

      expect(await ticket.balanceOf(wallet.address)).to.equal(toWei('10'))
    })
  })

  describe('redeem()', async () => {
    it('should redeem assets from the yield source', async () => {
      await depositToken.approve(prizePool.address, toWei('99'))
      await depositToken.mint(wallet.address, toWei('99'))
      await yieldSource.mock.supplyTokenTo.withArgs(toWei('99'), prizePool.address).returns()
      await prizePool.depositTo(wallet.address, toWei('99'), ticket.address, ethers.constants.AddressZero)
      
      await yieldSource.mock.redeemToken.withArgs(toWei('99')).returns(toWei('98'))
      await prizePool.withdrawInstantlyFrom(wallet.address, toWei('99'), ticket.address, toWei('99'))

      expect(await ticket.balanceOf(wallet.address)).to.equal('0')
      expect(await depositToken.balanceOf(wallet.address)).to.equal(toWei('98'))
    })
  })

  describe('token()', async () => {
    it('should return the yield source token', async () => {
      expect(await prizePool.token()).to.equal(depositToken.address)
    })
  })

  describe('canAwardExternal()', async () => {
    it('should not allow the prize pool to award its token, as its likely the receipt', async () => {
      expect(await prizePool.canAwardExternal(yieldSource.address)).to.equal(false)
    })
  })
})
