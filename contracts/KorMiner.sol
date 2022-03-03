// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract KorMiner is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct Miner {
        uint256 hashrate;
        uint256 numOfMiner;
        uint256 price;
    }

    address private usdcAddress;
    IERC20 private _token;
    
    mapping(uint256 => Miner) public miners;
    mapping(uint256 => uint256) public mintedMinerCount; // map hashrate to number
    mapping(uint256 => Miner) public tokenIdToMiner; // just need hash rate and number in this case

    uint256 public totalMinerTypes;

    constructor() ERC721("KorMiner", "KorMiner") {
    }

    function setUSDCAddress(address _tokenAddress) external onlyOwner {
        usdcAddress = _tokenAddress;
    }

    // numOfMiners should be multiplied by 4
    function setMiners(uint256 _hashrate, uint256 _numOfMiner, uint256 _price) external onlyOwner {
        Miner memory miner;
        for (uint256 i = 0; i < totalMinerTypes; i++) {
            miner = miners[i];
            if (miner.hashrate == _hashrate) {
                miner.numOfMiner = _numOfMiner * 4;
                miner.price = _price;
                return;
            }
        }
        miner = Miner({hashrate: _hashrate, numOfMiner: _numOfMiner * 4, price: _price});
        miners[totalMinerTypes] = miner;
        totalMinerTypes++;
    }

    // num 1 is equal to 1 / 4, and 2 is equal to 2 / 4
    function buyMiner(uint256 _hashrate, uint256 _num) external payable nonReentrant {
        Miner memory miner;
        for (uint256 i = 0; i < totalMinerTypes; i++) {
            miner = miners[i];
            if (miner.hashrate == _hashrate) {
                break;
            }
        }
        require(miner.hashrate > 0, "No matching miners");
        require(msg.value >= miner.price, "Not enough money");
        uint256 minted = mintedMinerCount[_hashrate];
        require(minted + _num <= miner.numOfMiner, "Exceed available number of miners");

        _tokenIds.increment();
        _safeMint(msg.sender, _tokenIds.current());

        miner.numOfMiner = _num;
        tokenIdToMiner[_tokenIds.current()] = miner;
        mintedMinerCount[_hashrate] += _num;
    }

    function distributeReward(uint256 totalReward) external onlyOwner {
        _token = IERC20(usdcAddress);
        uint256 totalPower;

        for (uint256 i = 0; i < totalMinerTypes; i++) {
            totalPower += miners[i].hashrate * miners[i].numOfMiner / 4;
        }

        Miner memory miner;
        for (uint256 i = 0; i < totalSupply(); i++) {
            miner = tokenIdToMiner[i + 1];
            uint256 percentOfToken = (totalReward * miner.hashrate) / totalPower;
            uint256 rewardOfToken = (percentOfToken * miner.numOfMiner * 2) / (3 * 4);
            _token.transfer(ownerOf(i + 1), rewardOfToken);
        }
    }

    // Function to withdraw all Ether from this contract.
    function withdraw() external onlyOwner{
        // send all Ether to owner
        // Owner can receive Ether since the address of owner is payable
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Failed to send Ether");
    }
}