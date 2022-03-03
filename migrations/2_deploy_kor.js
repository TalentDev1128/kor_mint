const KorMiner = artifacts.require("KorMiner");

module.exports = async function (deployer) {
  await deployer.deploy(KorMiner);
};
