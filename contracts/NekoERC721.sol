//SPDX-License-Identifier: MIT
pragma solidity >= 0.6.2 < 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NekoERC721 is ERC721, Ownable {	
	using Counters for Counters.Counter;

	Counters.Counter private currentId;			
	uint256 private max;
		
	event NekoMinted(uint256 tokenId, string metadata);

	constructor(string memory name, string memory symbol, uint256 _max) 
	public 
	ERC721(name, symbol) {
		_setBaseURI("https://arweave.net/");				
		max = _max;
	}

	function mintTo(address _to, string calldata _metadata)
	external  
	onlyOwner()
	{
		uint256 thisTokenId = currentId.current();	
		require(thisTokenId < max);

		_safeMint(_to, thisTokenId);
		_setTokenURI(thisTokenId, _metadata);

		emit NekoMinted(thisTokenId, _metadata);

		currentId.increment();	
	}

}
