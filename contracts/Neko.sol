pragma solidity >= 0.6.2 < 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Neko is ERC20 {   
	
	uint8 private constant TOKEN_DECIMALS = 8;
	uint256 private constant TOTAL_SUPPLY = 8888888888888888*10**8;

	constructor(address mintTo)
	ERC20("Lucky Cat", "NEKO") {
		_setupDecimals(TOKEN_DECIMALS);
		_mint(mintTo, TOTAL_SUPPLY);
	}
	
}
