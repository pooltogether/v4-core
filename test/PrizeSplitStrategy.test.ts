import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { ethers, artifacts } from 'hardhat';
import { Artifact } from 'hardhat/types';
import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Contract, ContractFactory, constants } from 'ethers';

const { getSigners } = ethers;
const { AddressZero } = constants;
const debug = require('debug')('ptv4:PrizeSplitStrategy');
const toWei = (val: string | number) => ethers.utils.parseEther('' + val)

describe('PrizeSplitStrategy', () => {
  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let wallet3: SignerWithAddress;
  let wallet4: SignerWithAddress;
  let prizeSplitStrategy: Contract;
  let ticket: Contract;
  let PrizePool: Artifact;
  let prizePool: MockContract;

  let prizeSplitStrategyFactory: ContractFactory
  let erc20MintableFactory: ContractFactory

  before(async () => {
    [wallet1, wallet2, wallet3, wallet4] = await getSigners();

    prizeSplitStrategyFactory = await ethers.getContractFactory(
      'PrizeSplitStrategy',
    );
    erc20MintableFactory = await ethers.getContractFactory(
      'ERC20Mintable',
    );
    PrizePool = await artifacts.readArtifact('PrizePool');
  });

  beforeEach(async () => {
    prizeSplitStrategy = await prizeSplitStrategyFactory.deploy();

    debug('mocking ticket and prizePool...');
    ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');
    prizePool = await deployMockContract(wallet1 as Signer, PrizePool.abi);
    await prizePool.mock.tokens.returns([ticket.address, ticket.address])

    debug('initialize prizeSplitStrategy...');
    await prizeSplitStrategy.initialize(prizePool.address);
  });

  describe("setPrizeSplits()", () => {
    it("should revert with invalid prize split target address", async () => {
      await expect(
        prizeSplitStrategy.setPrizeSplits([
          {
            target: AddressZero,
            percentage: 100,
            token: 0,
          },
        ])
      ).to.be.revertedWith(
        "PrizeSplit/invalid-prizesplit-target"
      );
    })

    it("should revert when calling setPrizeSplits from a non-owner address", async () => {
      prizeSplitStrategy = await prizeSplitStrategy.connect(wallet3);
      await expect(prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet3.address,
          percentage: 55,
          token: 1,
        },
        {
          target: wallet4.address,
          percentage: 120,
          token: 0,
        },
      ]))
        .to.be.revertedWith("Ownable: caller is not the owner");
    })

    it("should revert with single prize split config is equal to or above 100% percent", async () => {
      await expect(
        prizeSplitStrategy.setPrizeSplits([
          {
            target: wallet3.address,
            percentage: 1005,
            token: 0,
          },
        ])
      ).to.be.revertedWith(
        "PrizeSplit/invalid-prizesplit-percentage"
      );
    });

    it("should revert when multuple prize split configs is above 100% percent", async () => {
      await expect(
        prizeSplitStrategy.setPrizeSplits([
          {
            target: wallet3.address,
            percentage: 500,
            token: 0,
          },
          {
            target: wallet4.address,
            percentage: 501,
            token: 0,
          },
        ])
      ).to.be.revertedWith("PrizeSplit/invalid-prizesplit-percentage-total");
    });

    it("should revert with invalid prize split token enum", async () => {
      await expect(
        prizeSplitStrategy.setPrizeSplits([
          {
            target: wallet3.address,
            percentage: 500,
            token: 2,
          },
          {
            target: wallet4.address,
            percentage: 200,
            token: 0,
          },
        ])
      ).to.be.revertedWith('PrizeSplit/invalid-prizesplit-token')
    });

    it("should revert when setting a non-existent prize split config", async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 500,
          token: 0,
        },
      ])

      await expect(
        prizeSplitStrategy.setPrizeSplit(
          {
            target: wallet2.address,
            percentage: 300,
            token: 0,
          },
          1
        )
      ).to.be.revertedWith(
        "PrizeSplit/nonexistent-prizesplit"
      );
    });

    it("should set two split prize winners using valid percentages", async () => {
      await expect(prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 50,
          token: 0,
        },
        {
          target: wallet3.address,
          percentage: 500,
          token: 1,
        },
      ]))
        .to.emit(prizeSplitStrategy, "PrizeSplitSet")
        .withArgs(wallet2.address, 50, 0, 0)

      const prizeSplits = await prizeSplitStrategy.prizeSplits();

      // First Prize Split
      expect(prizeSplits[0].target)
        .to.equal(wallet2.address)
      expect(prizeSplits[0].percentage)
        .to.equal(50)
      expect(prizeSplits[0].token)
        .to.equal(0)

      // Second Prize Split
      expect(prizeSplits[1].target)
        .to.equal(wallet3.address)
      expect(prizeSplits[1].percentage)
        .to.equal(500)
      expect(prizeSplits[1].token)
        .to.equal(1)
    });

    it("should set two split prize configs and update the first prize split config", async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 50,
          token: 0,
        },
        {
          target: wallet3.address,
          percentage: 500,
          token: 0,
        },
      ]);
      await prizeSplitStrategy.setPrizeSplit(
        {
          target: wallet2.address,
          percentage: 150,
          token: 1,
        },
        0
      );

      const prizeSplits = await prizeSplitStrategy.prizeSplits();

      // First Prize Split
      expect(prizeSplits[0].target)
        .to.equal(wallet2.address)
      expect(prizeSplits[0].percentage)
        .to.equal(150)
      expect(prizeSplits[0].token)
        .to.equal(1)

      // Second Prize Split
      expect(prizeSplits[1].target)
        .to.equal(wallet3.address)
      expect(prizeSplits[1].percentage)
        .to.equal(500)
      expect(prizeSplits[1].token)
        .to.equal(0)
    });

    it("should set two split prize config and add a third prize split config", async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 50,
          token: 0,
        },
        {
          target: wallet3.address,
          percentage: 500,
          token: 0,
        },
      ]);

      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 50,
          token: 0,
        },
        {
          target: wallet3.address,
          percentage: 500,
          token: 0,
        },
        {
          target: wallet2.address,
          percentage: 150,
          token: 1,
        },
      ])

      const prizeSplits = await prizeSplitStrategy.prizeSplits();

      // First Prize Split
      expect(prizeSplits[0].target)
        .to.equal(wallet2.address)
      expect(prizeSplits[0].percentage)
        .to.equal(50)
      expect(prizeSplits[0].token)
        .to.equal(0)

      // Second Prize Split
      expect(prizeSplits[1].target)
        .to.equal(wallet3.address)
      expect(prizeSplits[1].percentage)
        .to.equal(500)
      expect(prizeSplits[1].token)
        .to.equal(0)

      // Third Prize Split
      expect(prizeSplits[2].target)
        .to.equal(wallet2.address)
      expect(prizeSplits[2].percentage)
        .to.equal(150)
      expect(prizeSplits[2].token)
        .to.equal(1)

    });

    it("should set two split prize config, update the second prize split config and add a third prize split config", async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 50,
          token: 0,
        },
        {
          target: wallet3.address,
          percentage: 500,
          token: 0,
        },
      ]);

      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 50,
          token: 0,
        },
        {
          target: wallet3.address,
          percentage: 300,
          token: 0,
        },
        {
          target: wallet2.address,
          percentage: 150,
          token: 1,
        },
      ])

      const prizeSplits = await prizeSplitStrategy.prizeSplits();
      // First Prize Split
      expect(prizeSplits[0].target)
        .to.equal(wallet2.address)
      expect(prizeSplits[0].percentage)
        .to.equal(50)
      expect(prizeSplits[0].token)
        .to.equal(0)

      // Second Prize Split
      expect(prizeSplits[1].target)
        .to.equal(wallet3.address)
      expect(prizeSplits[1].percentage)
        .to.equal(300)
      expect(prizeSplits[1].token)
        .to.equal(0)

      // Third Prize Split
      expect(prizeSplits[2].target)
        .to.equal(wallet2.address)
      expect(prizeSplits[2].percentage)
        .to.equal(150)
      expect(prizeSplits[2].token)
        .to.equal(1)
    });

    it("should set two split prize configs, update the first and remove the second prize split config", async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 50,
          token: 0,
        },
        {
          target: wallet3.address,
          percentage: 500,
          token: 0,
        },
      ]);

      await expect(prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 400,
          token: 0,
        },
      ])).to.emit(prizeSplitStrategy, "PrizeSplitRemoved")

      const prizeSplits = await prizeSplitStrategy.prizeSplits();
      expect(prizeSplits.length)
        .to.equal(1)

      // First Prize Split
      expect(prizeSplits[0].target)
        .to.equal(wallet2.address)
      expect(prizeSplits[0].percentage)
        .to.equal(400)
      expect(prizeSplits[0].token)
        .to.equal(0)
    });

    it("should set two split prize configs and a remove all prize split configs", async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 50,
          token: 0,
        },
        {
          target: wallet3.address,
          percentage: 500,
          token: 0,
        },
      ]);
      await expect(prizeSplitStrategy.setPrizeSplits([]))
        .to.emit(prizeSplitStrategy, "PrizeSplitRemoved").withArgs(0)

      const prizeSplits = await prizeSplitStrategy.prizeSplits();
      expect(prizeSplits.length)
        .to.equal(0)
    });
  })

  describe('distribute()', () => {
    it('should fail to capture award balance when prize split is unset', async () => {
      await expect(prizeSplitStrategy.distribute())
        .to.be.revertedWith('PrizeSplitStrategy/prize-split-unavailable')
    });

    it('should fail to capture award balance when prize split is below 100%', async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 500,
          token: 1,
        },
      ])
      await expect(prizeSplitStrategy.distribute())
        .to.be.revertedWith('PrizeSplitStrategy/invalid-prizesplit-percentage-total')
    });

    it('should award 100% of the captured balance to the PrizeReserve', async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 1000,
          token: 1,
        },
      ])
      await prizePool.mock.captureAwardBalance.returns(toWei('100'))
      await prizePool.mock.award.withArgs(wallet2.address, toWei('100'), ticket.address).returns()
      // Distribute Award
      const distribute = await prizeSplitStrategy.distribute()
      // Verify Contract Events
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'Distribute')
        .withArgs(toWei('100'))
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'PrizeSplitAwarded')
        .withArgs(wallet2.address, toWei('100'), ticket.address)
    });

    it('should award (50%/50%) the captured balance to the PrizeReserve and a secondary account.', async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 500,
          token: 1,
        },
        {
          target: wallet3.address,
          percentage: 500,
          token: 0,
        },
      ])
      await prizePool.mock.captureAwardBalance.returns(toWei('100'))
      // Mock PrizeReserve Award Sponsorhip
      await prizePool.mock.award.withArgs(wallet2.address, toWei('50'), ticket.address).returns()
      // Mock Secondary Wallet Award Sponsorhip
      await prizePool.mock.award.withArgs(wallet3.address, toWei('50'), ticket.address).returns()
      // Distribute Award
      const distribute = await prizeSplitStrategy.distribute()
      // Verify Contract Events
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'Distribute')
        .withArgs(toWei('100'))
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'PrizeSplitAwarded')
        .withArgs(wallet2.address, toWei('50'), ticket.address)
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'PrizeSplitAwarded')
        .withArgs(wallet3.address, toWei('50'), ticket.address)
    });

  })


})