// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KorMiner is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    AggregatorV3Interface internal priceFeed;

    uint256 constant public expireLimit = 4 * 365 * 24 * 60 * 60; // 4 years

    struct Miner {
        uint256 hashrate;
        uint256 numOfMiner;
        uint256 price;
        uint256 mintTime;
    }

    address public usdcAddress;
    IERC20 private _token;
    
    mapping(uint256 => Miner) public miners;
    mapping(uint256 => uint256) public mintedMinerCount; // map hashrate to number
    mapping(uint256 => Miner) public tokenIdToMiner; // just need hash rate and number in this case

    uint256 public totalMinerTypes;

    constructor() ERC721("KorMiner", "KorMiner") {
        // Ethereum mainnet: 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4
        // Rinkeby testnet: 0xdCA36F27cbC4E38aE16C4E9f99D39b42337F6dcf
        priceFeed = AggregatorV3Interface(0xdCA36F27cbC4E38aE16C4E9f99D39b42337F6dcf);
        
        // Ethereum mainnet: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // Rinkeby testnet: 0xD92E713d051C37EbB2561803a3b5FBAbc4962431
        usdcAddress = 0xD92E713d051C37EbB2561803a3b5FBAbc4962431;
    }

    function getLatestPrice() public view returns (uint256) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function isExpired (uint256 _tokenId) internal view returns(bool) {
        Miner memory miner = tokenIdToMiner[_tokenId];
        return (block.timestamp - miner.mintTime > expireLimit);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes calldata data) public override {
        require(!isExpired(_tokenId), "Expired item cannot be traded");
        super.safeTransferFrom(_from, _to, _tokenId, data);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) public override {
        require(!isExpired(_tokenId), "Expired item cannot be traded");
        super.safeTransferFrom(_from, _to, _tokenId);
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) public override {
        require(!isExpired(_tokenId), "Expired item cannot be traded");
        super.transferFrom(_from, _to, _tokenId);
    }

    function setUSDCAddress(address _usdcAddress) external onlyOwner {
        usdcAddress = _usdcAddress;
    }

    function forceExpire(uint256 _tokenId) external onlyOwner {
        require(isExpired(_tokenId), "This token is not expired yet");
        Miner memory miner = tokenIdToMiner[_tokenId];
        mintedMinerCount[miner.hashrate] -= miner.numOfMiner;
    }

    // numOfMiners should be multiplied by 4
    function setMiners(uint256 _hashrate, uint256 _numOfMiner, uint256 _price) external onlyOwner {
        for (uint256 i = 0; i < totalMinerTypes; i++) {
            if (miners[i].hashrate == _hashrate) {
                miners[i].numOfMiner = _numOfMiner * 4;
                miners[i].price = _price;
                return;
            }
        }
        Miner memory miner;
        miner = Miner({hashrate: _hashrate, numOfMiner: _numOfMiner * 4, price: _price, mintTime: 0});
        miners[totalMinerTypes] = miner;
        totalMinerTypes++;
    }

    // num 1 is equal to 1 / 4, and 2 is equal to 2 / 4
    function buyMiner(uint256 _hashrate, uint256 _num) external payable nonReentrant {
        uint256 currentPrice = getLatestPrice();
        Miner memory miner;
        for (uint256 i = 0; i < totalMinerTypes; i++) {
            miner = miners[i];
            if (miner.hashrate == _hashrate) {
                break;
            }
        }
        require(miner.hashrate > 0, "No matching miners");
        require(msg.value >= (miner.price * currentPrice * _num / 4), "Not enough money");
        uint256 minted = mintedMinerCount[_hashrate];
        require(minted + _num <= miner.numOfMiner, "Exceed available number of miners");

        _tokenIds.increment();
        _safeMint(msg.sender, _tokenIds.current());

        miner.numOfMiner = _num;
        miner.mintTime = block.timestamp;
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
            if (isExpired(i + 1))
                break;
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