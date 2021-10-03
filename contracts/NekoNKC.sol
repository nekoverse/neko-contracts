//SPDX-License-Identifier: MIT
pragma solidity >= 0.6.2 < 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "hardhat/console.sol";
import "./NekoNKCAuction.sol";

contract NekoNKC is ERC721, Ownable {

	modifier ownsAtLeastOne {
		require(balanceOf(msg.sender) > 0, "NEKO NKC NFT: must have at least one token");
		_;
	}

	modifier onlyAuction() {
		require(msg.sender == address(auction), "NEKO NKC NFT: only auction can call this");
		_;
	}

	uint public constant EXP = 6;					// precision exponent
	uint public constant SCALE = 10**EXP;			// precision scale

	// external contract references
	NekoNKCAuction private auction;					// NEKO Auction reference

	uint public maxTokens;							// max token count, set at construction;
	uint public emissionPct;						// fraction of TVL to emit as a winning;
	uint public tvl;								// total value locked - this is the prize pool
	uint public totalMintValue; 					// total mint value (sum of mint values)
	address[] private mintOwner;					// token id => wallet that can mint
	mapping (address => uint) private mintOwnerRev; // address => token id
	uint[] private mintValue;						// token id => value at mint
	uint[] private winnings;						// token id => accrued unclaimed winnings
	bool[] private isInit;							// token id => is initialized
	bool[] private isMinted;						// token id => is minted
	mapping (uint => string) private metadata;		// token id => metadata url

	uint private randNonce = 0;						// used for randomness
	uint[] private accruals; 						// this is used to draw the winner

	event NekoMinted(uint tokenId, string metadata);
	event NekoWin(uint tokenId, uint amount);

	constructor(string memory name, string memory symbol, uint _maxTokens)
	public
	ERC721(name, symbol)
	{
		_setBaseURI("https://arweave.net/");

		maxTokens = _maxTokens;
		mintOwner = new address[](maxTokens);
		mintValue = new uint[](maxTokens);
		winnings = new uint[](maxTokens);
		accruals = new uint[](maxTokens);
		isInit = new bool[](maxTokens);
		isMinted = new bool[](maxTokens);

		emissionPct = 1 * 10**(EXP-2); 	// default 1%
	}

	receive()
    external payable
    {
        require(msg.data.length == 0);
		tvl = SafeMath.add(tvl, msg.value);
	}

	function mint(uint tokenId, address to)
	external payable
	{
		require(isInit[tokenId] && !isMinted[tokenId], "NEKO NKC NFT: token must be initialized, but not minted");
		require(tokenId < maxTokens, "NEKO NKC NFT: only maxTokens amount can be minted");
		require(mintOwner[tokenId] == to, "NEKO NKC NFT: only future owner can mint");
		require(mintValue[tokenId] == msg.value, "NEKO NKC NFT: must send the exact mint value");

		isMinted[tokenId] = true;

		tvl = SafeMath.add(tvl, mintValue[tokenId]);
		totalMintValue = SafeMath.add(totalMintValue, mintValue[tokenId]);
		accruals[tokenId] = tokenId > 0 ? SafeMath.add(accruals[tokenId-1], mintValue[tokenId])
										: accruals[tokenId] = mintValue[tokenId];

		_safeMint(to, tokenId);
		_setTokenURI(tokenId, metadata[tokenId]);

		emit NekoMinted(tokenId, metadata[tokenId]);
	}

	function claimWinnings()
	external
	ownsAtLeastOne()
	{
		uint ownedTokens = balanceOf(msg.sender);
		uint drawAmount;
		for (uint i = 0; i < ownedTokens; i++) {
			uint tokenId = tokenOfOwnerByIndex(msg.sender, i);
			drawAmount = winnings[tokenId];
			winnings[tokenId] = 0;
		}

		(bool sent, bytes memory data) = msg.sender.call{value: drawAmount}(""); // pay draw Amount in Avax
		require(sent, "NEKO NKC NFT: Failed to send Avax");
	}

	// only owner

	function init(uint tokenId, string calldata _metadata)
	external
	onlyOwner()
	{
		require(!isInit[tokenId]);
		metadata[tokenId] = _metadata;
		isInit[tokenId] = true;
	}

	function assignMintOwner(uint tokenId, address owner, uint value)
	external
	onlyAuction()
	{
		mintOwner[tokenId] = owner;
		mintValue[tokenId] = value;
		mintOwnerRev[owner] = tokenId;
	}

	function drawPrize(uint256 time)
	external
	onlyOwner()
	{
		uint winnerTokenId = _chooseWinningToken(time);
		uint prize = _calcPrizeAmount(tvl, emissionPct);
		winnings[winnerTokenId] = SafeMath.add(winnings[winnerTokenId], prize);
		tvl = SafeMath.sub(tvl, prize);
		emit NekoWin(winnerTokenId, prize);
	}

	function setAuctionContract(address auctionAddr)
	external
	onlyOwner()
	{
		auction = NekoNKCAuction(auctionAddr);
	}

	function setEmissionPct(uint pct)
	external
	onlyOwner()
	{
		require(pct >= 0 && pct <= SCALE, "NEKO NKC NFT: must be between 0 and 100000, inclusive");
		emissionPct = pct;
	}

	// privates

	function _chooseWinningToken(uint time)
	private
	returns (uint)
	{
		uint r = _random(time);
		for (uint tokenId; tokenId < maxTokens; tokenId++) {
			uint cutoff = _normalize(accruals[tokenId], totalMintValue);
			if (r < cutoff) {
				return tokenId;
			}
		}
	}

	function _random(uint time)
	private
	returns (uint)
	{
		randNonce++;
		uint randomHash = uint(keccak256(abi.encodePacked(time, msg.sender, randNonce)));
		return randomHash % SCALE;
	}

	// calcs

	function _normalize(uint n, uint base)
	private pure
	returns (uint normed)
	{
		normed = SafeMath.div(SafeMath.mul(n, SCALE), base);
	}

	function _calcPrizeAmount(uint _tvl, uint _frac)
	private pure
	returns (uint amount)
	{
		amount = SafeMath.div(SafeMath.mul(_tvl, _frac), SCALE);
	}

	// views

	function mintValueOf(uint tokenId)
	external view
	returns (uint)
	{
		return mintValue[tokenId];
	}

	function winningsOf(uint tokenId)
	external view
	returns (uint)
	{
		return winnings[tokenId];
	}

	function chanceOfWinning(uint tokenId)
	external view
	returns (uint scaled, uint base)
	{
		scaled = SafeMath.div(SafeMath.mul(mintValue[tokenId], SCALE), totalMintValue);
		base = SCALE;
	}

	function totalValueLocked()
	external view
	returns (uint)
	{
		return tvl;
	}

	function totalValueMinted()
	external view
	returns (uint)
	{
		return totalMintValue;
	}

	function assignedToken(address addr)
	external view
	returns (uint)
	{
		uint tokenId = mintOwnerRev[addr];
		require(mintOwner[tokenId] == addr, "NEKO NKC NFT: no assigned token");
		return tokenId;
	}

	function mintOwnerOf(uint tokenId)
	external view
	returns (address owner, uint value)
	{
		owner = mintOwner[tokenId];
		value = mintValue[tokenId];
	}

	function isInitialized(uint tokenId)
	external view
	returns (bool)
	{
		return isInit[tokenId];
	}

	function isAlreadyMinted(uint tokenId)
	external view
	returns (bool)
	{
		return isMinted[tokenId];
	}
}
