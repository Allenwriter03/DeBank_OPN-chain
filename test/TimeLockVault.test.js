const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const DAY = 24 * 60 * 60;
const NATIVE = "0x0000000000000000000000000000000000000000";

async function deployVault() {
  const [owner, alice, bob, feeRecipient] = await ethers.getSigners();

  const TimeLockVault = await ethers.getContractFactory("TimeLockVault");
  const vault = await TimeLockVault.deploy(
    owner.address,
    feeRecipient.address,
    50, // 0.5% lock fee
    50, // 0.5% claim fee
    200 // 2% early withdraw fee
  );
  await vault.waitForDeployment();

  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const usdc = await MockERC20.deploy("Mock USDC", "mUSDC", 6);
  await usdc.waitForDeployment();
  await usdc.mint(alice.address, ethers.parseUnits("1000", 6));
  await usdc.mint(bob.address, ethers.parseUnits("1000", 6));

  return { vault, usdc, owner, alice, bob, feeRecipient };
}

describe("TimeLockVault", function () {
  it("locks native OPN and lets the owner claim after maturity", async function () {
    const { vault, alice } = await deployVault();

    await vault.connect(alice).createLock(NATIVE, 0, 30 * DAY, { value: ethers.parseEther("10") });
    const [lockId] = await vault.getUserLockIds(alice.address);
    const lock = await vault.getLock(lockId);
    expect(lock.owner).to.equal(alice.address);
    expect(lock.claimed).to.equal(false);

    await time.increase(31 * DAY);

    const before = await ethers.provider.getBalance(alice.address);
    const tx = await vault.connect(alice).claim(lockId);
    const receipt = await tx.wait();
    const gasCost = receipt.gasUsed * receipt.gasPrice;
    const after = await ethers.provider.getBalance(alice.address);

    // locked amount is 9.95 (10 minus the 0.5% lock fee taken at creation);
    // claim then takes another 0.5% claim fee on that 9.95 -> 9.90025 received
    expect(after - before + gasCost).to.be.closeTo(ethers.parseEther("9.90025"), ethers.parseEther("0.001"));
  });

  it("rejects a claim attempt from a wallet that does not own the lock", async function () {
    const { vault, alice, bob } = await deployVault();

    await vault.connect(alice).createLock(NATIVE, 0, 30 * DAY, { value: ethers.parseEther("5") });
    const [lockId] = await vault.getUserLockIds(alice.address);

    await time.increase(31 * DAY);

    await expect(vault.connect(bob).claim(lockId)).to.be.revertedWith("not your lock");
  });

  it("rejects claiming the same lock twice", async function () {
    const { vault, alice } = await deployVault();

    await vault.connect(alice).createLock(NATIVE, 0, 1 * DAY, { value: ethers.parseEther("1") });
    const [lockId] = await vault.getUserLockIds(alice.address);

    await time.increase(2 * DAY);
    await vault.connect(alice).claim(lockId);

    await expect(vault.connect(alice).claim(lockId)).to.be.revertedWith("already claimed");
  });

  it("allows early withdrawal before maturity, charging the bigger penalty fee instead of blocking it", async function () {
    const { vault, alice } = await deployVault();

    await vault.connect(alice).createLock(NATIVE, 0, 30 * DAY, { value: ethers.parseEther("10") });
    const [lockId] = await vault.getUserLockIds(alice.address);

    // locked amount is 9.95 (10 minus the 0.5% lock fee taken at creation);
    // claiming immediately, well before the 30-day unlock, applies the 2% early fee to that 9.95
    await expect(vault.connect(alice).claim(lockId))
      .to.emit(vault, "LockClaimed")
      .withArgs(lockId, alice.address, ethers.parseEther("9.751"), ethers.parseEther("0.199"), true);
  });

  it("lets a user top up their own lock without changing the unlock date", async function () {
    const { vault, alice } = await deployVault();

    await vault.connect(alice).createLock(NATIVE, 0, 30 * DAY, { value: ethers.parseEther("1") });
    const [lockId] = await vault.getUserLockIds(alice.address);
    const before = await vault.getLock(lockId);

    await vault.connect(alice).topUp(lockId, 0, { value: ethers.parseEther("1") });
    const after = await vault.getLock(lockId);

    expect(after.unlockTime).to.equal(before.unlockTime);
    expect(after.amount).to.be.gt(before.amount);
  });

  it("rejects topping up someone else's lock", async function () {
    const { vault, alice, bob } = await deployVault();

    await vault.connect(alice).createLock(NATIVE, 0, 30 * DAY, { value: ethers.parseEther("1") });
    const [lockId] = await vault.getUserLockIds(alice.address);

    await expect(
      vault.connect(bob).topUp(lockId, 0, { value: ethers.parseEther("1") })
    ).to.be.revertedWith("not your lock");
  });

  it("supports locking an approved ERC-20 (mock USDC) and rejects unapproved tokens", async function () {
    const { vault, usdc, alice, owner } = await deployVault();

    const amount = ethers.parseUnits("100", 6);
    await usdc.connect(alice).approve(await vault.getAddress(), amount);

    // not yet approved by the owner
    await expect(vault.connect(alice).createLock(await usdc.getAddress(), amount, 30 * DAY)).to.be.revertedWith(
      "token not supported"
    );

    await vault.connect(owner).setSupportedToken(await usdc.getAddress(), true);
    await vault.connect(alice).createLock(await usdc.getAddress(), amount, 30 * DAY);

    const [lockId] = await vault.getUserLockIds(alice.address);
    const lock = await vault.getLock(lockId);
    expect(lock.amount).to.equal(ethers.parseUnits("99.5", 6)); // minus 0.5% lock fee
  });

  it("lets the owner pause new locks while leaving existing claims open", async function () {
    const { vault, alice, owner } = await deployVault();

    await vault.connect(alice).createLock(NATIVE, 0, 1 * DAY, { value: ethers.parseEther("1") });
    const [lockId] = await vault.getUserLockIds(alice.address);

    await vault.connect(owner).pause();

    await expect(
      vault.connect(alice).createLock(NATIVE, 0, 1 * DAY, { value: ethers.parseEther("1") })
    ).to.be.revertedWithCustomError(vault, "EnforcedPause");

    // claiming the existing lock still works while paused
    await time.increase(2 * DAY);
    await expect(vault.connect(alice).claim(lockId)).to.not.be.reverted;
  });

  it("blocks a non-owner from changing fees or the fee recipient", async function () {
    const { vault, alice } = await deployVault();

    await expect(vault.connect(alice).setFees(100, 100, 300)).to.be.revertedWithCustomError(
      vault,
      "OwnableUnauthorizedAccount"
    );
    await expect(vault.connect(alice).setFeeRecipient(alice.address)).to.be.revertedWithCustomError(
      vault,
      "OwnableUnauthorizedAccount"
    );
  });

  it("caps fees so the owner can never set them above 5%", async function () {
    const { vault, owner } = await deployVault();
    await expect(vault.connect(owner).setFees(600, 0, 0)).to.be.revertedWith("fee too high");
  });
});
