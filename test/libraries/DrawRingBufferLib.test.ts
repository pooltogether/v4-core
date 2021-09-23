import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { utils, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { getSigners } = ethers;

describe('DrawRingBufferLib', () => {
  let drawRingBufferLib: Contract;
  let drawRingBufferLibFactory: ContractFactory;

  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;

  before(async () => {
    [wallet1, wallet2] = await getSigners();
    drawRingBufferLibFactory = await ethers.getContractFactory('DrawRingBufferLibExposed');
  })

  beforeEach(async () => {
    drawRingBufferLib = await drawRingBufferLibFactory.deploy('255');
  });

  describe('isNotInitialized()', () => {
    it('should return TRUE to signal an uninitalized DrawHistory', async () => {
      expect(await drawRingBufferLib._isNotInitialized({
        lastDrawId: 0,
        nextIndex: 0,
        cardinality: 256
      })).to.eql(true)
    })

    it('should return FALSE to signal an initalized DrawHistory', async () => {
      expect(await drawRingBufferLib._isNotInitialized({
        lastDrawId: 1,
        nextIndex: 1,
        cardinality: 256
      })).to.eql(false)
    })
  })

  describe('push()', () => {
    it('should return the next valid Buffer struct assuming DrawHistory with 0 draws', async () => {
      const nextBuffer = await drawRingBufferLib._push({
        lastDrawId: 0,
        nextIndex: 0,
        cardinality: 256
      }, 0)
      expect(nextBuffer.lastDrawId).to.eql(0)
      expect(nextBuffer.nextIndex).to.eql(1)
      expect(nextBuffer.cardinality).to.eql(256)
    })

    it('should return the next valid Buffer struct assuming DrawHistory with 1 draws', async () => {
      const nextBuffer = await drawRingBufferLib._push({
        lastDrawId: 0,
        nextIndex: 1,
        cardinality: 256
      }, 1)
      expect(nextBuffer.lastDrawId).to.eql(1)
      expect(nextBuffer.nextIndex).to.eql(2)
      expect(nextBuffer.cardinality).to.eql(256)
    })

    it('should return the next valid Buffer struct assuming DrawHistory with 255 draws', async () => {
      const nextBuffer = await drawRingBufferLib._push({
        lastDrawId: 255,
        nextIndex: 255,
        cardinality: 256
      }, 256)
      expect(nextBuffer.lastDrawId).to.eql(256)
      expect(nextBuffer.nextIndex).to.eql(0)
      expect(nextBuffer.cardinality).to.eql(256)
    })

    it('should fail to create new Buffer struct due to not contiguous Draw ID', async () => {
      const Buffer = {
        lastDrawId: 0,
        nextIndex: 1,
        cardinality: 256
      }
      expect(drawRingBufferLib._push(Buffer, 4))
        .to.be.revertedWith('DRB/must-be-contig')
    })
  });

  describe('getIndex()', () => {
    it('should return valid draw index assuming DrawHistory with 1 draw ', async () => {
      const Buffer = {
        lastDrawId: 0,
        nextIndex: 1,
        cardinality: 256
      }
      expect(await drawRingBufferLib._getIndex(Buffer, 0)).to.eql(0)
    })

    it('should return valid draw index assuming DrawHistory with 255 draws', async () => {
      const Buffer = {
        lastDrawId: 255,
        nextIndex: 0,
        cardinality: 256
      }
      expect(await drawRingBufferLib._getIndex(Buffer, 255)).to.eql(255)
    })

    it('should fail to return index since Draw has not been pushed', async () => {
      expect(drawRingBufferLib._getIndex({
        lastDrawId: 1,
        nextIndex: 2,
        cardinality: 256
      }, 255))
        .to.be.revertedWith('DRB/future-draw')
    })

    it('should fail to return index since Draw has expired', async () => {
      expect(drawRingBufferLib._getIndex({
        lastDrawId: 256,
        nextIndex: 1,
        cardinality: 256
      }, 0))
        .to.be.revertedWith('DRB/expired-draw')
    })
  });
})
