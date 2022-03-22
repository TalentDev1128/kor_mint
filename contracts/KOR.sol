// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KOR is ERC721Enumerable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter internal _tokenIds;
    address public owner;

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    struct Miner {
        string minerType;
        uint256 hashrate;
        uint256 numOfMiner;
        uint256 price;
    }

    struct Token {
        uint256 index;
        uint256 amount;
        uint256 mintTime;
    }

    uint256 constant public expireLimit = 4 * 365 * 24 * 60 * 60; // 4 years
    AggregatorV3Interface internal priceFeed;

    address public usdcAddress;
    IERC20 internal usdcToken;
    string public _baseTokenURI;
    
    mapping(uint256 => Miner) public miners; // miner index to miner
    mapping(uint256 => uint256) public mintedMinerCount; // miner index to minted amount (1 = 1/4)
    mapping(uint256 => Token) public tokenIdToToken; // nft token Id to Token

    uint256 public totalMiner;

    constructor() ERC721("KOR", "KOR") {
        owner = msg.sender;

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

    function isExpired (uint256 _tokenId) public view returns(bool) {
        Token memory token = tokenIdToToken[_tokenId];
        return (block.timestamp - token.mintTime > expireLimit);
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
        Token memory token = tokenIdToToken[_tokenId];
        uint256 minerIndex = token.index;
        mintedMinerCount[minerIndex] -= token.amount;
    }

    // numOfMiners should be multiplied by 4
    function addMiner(string memory _minerType, uint256 _hashrate, uint256 _numOfMiner, uint256 _price) external onlyOwner {
        Miner memory miner = Miner({minerType: _minerType, hashrate: _hashrate, numOfMiner: _numOfMiner * 4, price: _price});
        miners[totalMiner] = miner;
        totalMiner++;
    }

    // numOfMiners should be multiplied by 4
    function updateMiner(uint256 index, string memory _minerType, uint256 _hashrate, uint256 _numOfMiner, uint256 _price) external onlyOwner {
        require(index < totalMiner, "index out of bounds");
        miners[index].minerType = _minerType;
        miners[index].hashrate = _hashrate;
        miners[index].numOfMiner = _numOfMiner * 4;
        miners[index].price = _price;
    }

    // num 1 is equal to 1 / 4, and 2 is equal to 2 / 4
    function buyMiner(uint256 index, uint256 _num) external payable nonReentrant {
        require(index < totalMiner, "index out of bounds");
        Miner memory miner = miners[index];
        uint256 currentPrice = getLatestPrice();
        require(msg.value >= (miner.price * currentPrice * _num / 4), "Not enough money");

        uint256 minted = mintedMinerCount[index];
        require(minted + _num <= miner.numOfMiner, "Exceed available number of miners");

        _tokenIds.increment();
        _safeMint(msg.sender, _tokenIds.current());

        Token memory token;
        token.index = index;
        token.amount = _num;
        token.mintTime = block.timestamp;

        tokenIdToToken[_tokenIds.current()] = token;
        mintedMinerCount[index] += _num;
    }

    function distributeReward(uint256 totalReward) external onlyOwner {
        usdcToken = IERC20(usdcAddress);
        uint256 totalPower;

        for (uint256 i = 0; i < totalMiner; i++) {
            totalPower += miners[i].hashrate * miners[i].numOfMiner / 4;
        }

        Token memory token;
        for (uint256 i = 0; i < totalSupply(); i++) {
            if (isExpired(i + 1))
                break;
            token = tokenIdToToken[i + 1];
            uint256 minerIndex = token.index;
            
            uint256 percentOfToken = (totalReward * miners[minerIndex].hashrate) / totalPower;
            uint256 rewardOfToken = (percentOfToken * token.amount * 2) / (3 * 4);
            usdcToken.transfer(ownerOf(i + 1), rewardOfToken);
        }
    }

    // Function to withdraw all Ether from this contract.
    function withdraw() external onlyOwner{
        // send all Ether to owner
        // Owner can receive Ether since the address of owner is payable
        (bool success, ) = owner.call{value: address(this).balance}("");
        require(success, "Failed to send Ether");
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }
}