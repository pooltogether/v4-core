import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, constants, Contract, ContractFactory, BigNumber } from 'ethers';
import { ethers, artifacts } from 'hardhat';

const { getSigners } = ethers;
const { defaultAbiCoder: encoder, parseEther: toWei } = utils;
const { AddressZero } = constants;

describe('PrizeDistributorV2', () => {
    let wallet1: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let wallet3: SignerWithAddress;
    let vault: SignerWithAddress;

    let token: Contract;
    let ticket: Contract;
    let prizeDistributorV2: Contract;
    let drawCalculator: MockContract;

    before(async () => {
        [wallet1, wallet2, wallet3, vault] = await getSigners();
    });

    beforeEach(async () => {
        const erc20MintableFactory: ContractFactory = await ethers.getContractFactory(
            'ERC20Mintable',
        );

        token = await erc20MintableFactory.deploy('Token', 'TOK');
        ticket = await erc20MintableFactory.deploy('Ticket', 'TIC');

        let IDrawCalculator = await artifacts.readArtifact('IDrawCalculatorV3');
        drawCalculator = await deployMockContract(wallet1, IDrawCalculator.abi);

        const PrizeDistributorV2Factory: ContractFactory = await ethers.getContractFactory(
            'PrizeDistributorV2',
        );

        prizeDistributorV2 = await PrizeDistributorV2Factory.deploy(
            wallet1.address,
            ticket.address,
            drawCalculator.address,
            vault.address,
        );

        await ticket.mint(vault.address, toWei('1000'));
        await ticket.connect(vault).approve(prizeDistributorV2.address, toWei('10000000'));
    });

    /**
     * @description Test claim(ITicket _ticket,address _user,uint32[] calldata _drawIds,bytes calldata _data) function
     * -= Expected Behavior =-
     * 1. calculate drawPayouts for user, ticket, drawIds and data(picks)
     * FOR
     * 2. update Draw payout amount for each drawId
     * 3. emit ClaimedDraw event
     * END FOR
     * 4. transfer total drawPayouts to user
     * 5. return totalPayout
     */
    describe('claim(ITicket _ticket,address _user,uint32[] calldata _drawIds,bytes calldata _data))', () => {
        let pickIndices: string[][];

        beforeEach(() => {
            pickIndices = [['1']];
        });

        it('should SUCCEED to claim and emit ClaimedDraw event', async () => {
            await drawCalculator.mock.calculate
                .withArgs(ticket.address, wallet1.address, [1], pickIndices)
                .returns([toWei('10')], '0x');

            await expect(
                prizeDistributorV2.claim(ticket.address, wallet1.address, [1], pickIndices),
            )
                .to.emit(prizeDistributorV2, 'ClaimedDraw')
                .withArgs(wallet1.address, 1, toWei('10'), pickIndices[0]);
        });

        it('should SUCCEED to payout the difference if user claims more', async () => {
            await drawCalculator.mock.calculate
                .withArgs(ticket.address, wallet1.address, [1], pickIndices)
                .returns([toWei('10')], '0x');

            await expect(
                prizeDistributorV2.claim(ticket.address, wallet1.address, [1], pickIndices),
            )
                .to.emit(prizeDistributorV2, 'ClaimedDraw')
                .withArgs(wallet1.address, 1, toWei('10'), pickIndices[0]);

            await drawCalculator.mock.calculate
                .withArgs(ticket.address, wallet1.address, [1], pickIndices)
                .returns([toWei('20')], '0x');

            await expect(
                prizeDistributorV2.claim(ticket.address, wallet1.address, [1], pickIndices),
            )
                .to.emit(prizeDistributorV2, 'ClaimedDraw')
                .withArgs(wallet1.address, 1, toWei('10'), pickIndices[0]);

            expect(await prizeDistributorV2.getDrawPayoutBalanceOf(wallet1.address, 1)).to.equal(
                toWei('20'),
            );
        });

        it('should REVERT on 2.update because the prize was previously claimed', async () => {
            await drawCalculator.mock.calculate
                .withArgs(ticket.address, wallet1.address, [0], pickIndices)
                .returns([toWei('10')], '0x');

            await prizeDistributorV2.claim(ticket.address, wallet1.address, [0], pickIndices);

            await expect(
                prizeDistributorV2.claim(ticket.address, wallet1.address, [0], pickIndices),
            ).to.be.revertedWith('PDistV2/zero-payout');
        });
    });

    /**
     * @description Test setDrawCalculator(DrawCalculatorInterface _newCalculator) function
     * -= Expected Behavior =-
     * 1. authorize the `msg.sender` has OWNER or MANAGER role
     * 2. update global drawCalculator variable
     * 3. emit DrawCalculatorSet event
     */
    describe('setDrawCalculator(DrawCalculatorInterface _newCalculator)', () => {
        it('should SUCCEED to update the drawCalculator global variable if owner', async () => {
            expect(await prizeDistributorV2.setDrawCalculator(wallet3.address))
                .to.emit(prizeDistributorV2, 'DrawCalculatorSet')
                .withArgs(wallet1.address, wallet3.address);
        });

        it('should SUCCEED to update the drawCalculator global variable if manager', async () => {
            await prizeDistributorV2.setManager(wallet2.address);

            expect(await prizeDistributorV2.connect(wallet2).setDrawCalculator(wallet3.address))
                .to.emit(prizeDistributorV2, 'DrawCalculatorSet')
                .withArgs(wallet2.address, wallet3.address);
        });

        it('should REVERT on 1.authorized because wallet is NOT an OWNER or MANAGER', async () => {
            const PrizeDistributorV2Unauthorized = prizeDistributorV2.connect(wallet3);
            await expect(
                PrizeDistributorV2Unauthorized.setDrawCalculator(AddressZero),
            ).to.be.revertedWith('Manageable/caller-not-manager-or-owner');
        });

        it('should REVERT on 2.update because the drawCalculator address is address zero', async () => {
            await expect(prizeDistributorV2.setDrawCalculator(AddressZero)).to.be.revertedWith(
                'PDistV2/calc-not-zero-address',
            );
        });
    });

    /**
     * @description Test setTokenVault(address _tokenVault) function
     * -= Expected Behavior =-
     * 1. authorize the `msg.sender` has OWNER or MANAGER role
     * 2. update global tokenVault variable
     * 3. emit TokenVaultSet event
     */
    describe('setTokenVault(address _tokenVault)', () => {
        it('should SUCCEED to update the tokenVault global variable if owner', async () => {
            expect(await prizeDistributorV2.setTokenVault(wallet3.address))
                .to.emit(prizeDistributorV2, 'TokenVaultSet')
                .withArgs(wallet1.address, wallet3.address);
        });

        it('should SUCCEED to update the tokenVault global variable if manager', async () => {
            await prizeDistributorV2.setManager(wallet2.address);

            expect(await prizeDistributorV2.connect(wallet2).setTokenVault(wallet3.address))
                .to.emit(prizeDistributorV2, 'TokenVaultSet')
                .withArgs(wallet2.address, wallet3.address);
        });

        it('should REVERT on 1.authorized because wallet is NOT an OWNER or MANAGER', async () => {
            await expect(
                prizeDistributorV2.connect(wallet2).setTokenVault(wallet3.address),
            ).to.be.revertedWith('Manageable/caller-not-manager-or-owner');
        });

        it('should REVERT on 2.update because the tokenVault address is address zero', async () => {
            await expect(prizeDistributorV2.setTokenVault(AddressZero)).to.be.revertedWith(
                'PDistV2/vault-not-zero-address',
            );
        });
    });

    /**
     * @description Test withdrawERC20(IERC20 _erc20Token, address _to, uint256 _amount) function
     * -= Expected Behavior =-
     * 1. authorize the `msg.sender` has OWNER or MANAGER role
     * 2. require _to address is not NULL
     * 3. require _erc20Token address is not NULL
     * 4. transfer ERC20 amount to _to address
     * 5. emit ERC20Withdrawn event
     * 6. return true
     */

    describe('withdrawERC20(IERC20 _erc20Token, address _to, uint256 _amount)', () => {
        let withdrawAmount: BigNumber = toWei('100');

        beforeEach(async () => {
            await token.mint(prizeDistributorV2.address, toWei('1000'));
        });

        it('should SUCCEED to withdraw ERC20 tokens as owner', async () => {
            await expect(
                prizeDistributorV2.withdrawERC20(token.address, wallet1.address, withdrawAmount),
            )
                .to.emit(prizeDistributorV2, 'ERC20Withdrawn')
                .withArgs(token.address, wallet1.address, withdrawAmount);
        });

        it('should REVERT on 1.authorize because from address is not an OWNER or MANAGER', async () => {
            expect(
                prizeDistributorV2
                    .connect(wallet2)
                    .withdrawERC20(token.address, wallet1.address, withdrawAmount),
            ).to.be.revertedWith('Manageable/caller-not-manager-or-owner');
        });

        it('should REVERT on 2.require because the recipient address is NULL', async () => {
            await expect(
                prizeDistributorV2.withdrawERC20(token.address, AddressZero, withdrawAmount),
            ).to.be.revertedWith('PDistV2/to-not-zero-address');
        });

        it('should REVERT on 3.require because the ERC20 address is NULL', async () => {
            await expect(
                prizeDistributorV2.withdrawERC20(AddressZero, wallet1.address, withdrawAmount),
            ).to.be.revertedWith('PDistV2/ERC20-not-zero-address');
        });
    });

    describe('getDrawCalculator()', () => {
        it('should SUCCEED to read an empty Draw ID => DrawCalculator mapping', async () => {
            expect(await prizeDistributorV2.getDrawCalculator()).to.equal(drawCalculator.address);
        });
    });

    describe('getDrawPayoutBalanceOf()', () => {
        it('should return the user payout for draw before claiming a payout', async () => {
            expect(await prizeDistributorV2.getDrawPayoutBalanceOf(wallet1.address, 0)).to.equal(
                '0',
            );
        });
    });

    describe('getToken()', () => {
        it('should successfully read global token variable', async () => {
            expect(await prizeDistributorV2.getToken()).to.equal(ticket.address);
        });
    });

    describe('getTokenVault()', () => {
        it('should successfully read global tokenVault variable', async () => {
            expect(await prizeDistributorV2.getTokenVault()).to.equal(vault.address);
        });
    });
});
