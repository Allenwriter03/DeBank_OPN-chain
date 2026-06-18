const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "OPN");


  const feeRecipient = process.env.FEE_RECIPIENT || deployer.address;
  const lockFeeBps = 50;
  const claimFeeBps = 50;
  const earlyWithdrawFeeBps = 200; 
  
  // -----------------------------------------------------------------------------

  const TimeLockVault = await hre.ethers.getContractFactory("TimeLockVault");
  const vault = await TimeLockVault.deploy(
    deployer.address,
    feeRecipient,
    lockFeeBps,
    claimFeeBps,
    earlyWithdrawFeeBps
  );

  await vault.waitForDeployment();
  const address = await vault.getAddress();

  console.log("\nTimeLockVault deployed to:", address);
  console.log("Owner:", deployer.address);
  console.log("Fee recipient:", feeRecipient);
  console.log("\nSave this address — you'll need it for the dashboard and for the");
  console.log("Builders Programme submission (builders.iopn.tech).");
  console.log("\nNext: if you plan to support an ERC-20 like USDC, call");
  console.log("  setSupportedToken(<token address>, true)");
  console.log("from the owner wallet before anyone tries to lock that token.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
