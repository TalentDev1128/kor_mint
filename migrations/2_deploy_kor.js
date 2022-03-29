const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");
const KOR = artifacts.require("KOR");

module.exports = async function (deployer) {
  const existing = await deployProxy(KOR, [], { deployer });
  console.log("Deployed", existing.address);
};
