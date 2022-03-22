const KOR = artifacts.require("KOR");

module.exports = async function (deployer) {
  await deployer.deploy(KOR);
};
