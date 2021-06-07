//SPDX-License-Identifier: MIT
pragma solidity >= 0.6.2 < 0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IPangolinRouter.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IWAVAX.sol";
import "neko/contracts/Neko.sol";

contract NekoLottery is Ownable {    	
	using Counters for Counters.Counter;
	
	uint256 public constant SCALE = 8;
	uint256 public constant PRIZE_PART = 90;
	uint256 public constant PRIZE_BASE = 100;

	IPangolinRouter public immutable router;
	IWAVAX public immutable wavax;
	Neko public immutable token;	
	uint256 public immutable maxPlayers;

	uint private _randNonce = 0;
	Counters.Counter private _drawNo;	

	uint256 private _playerCount; // number of players in the current draw
	uint256 private _totalAmount; // total amount deposited
	uint256 private _maxAmount; // max amount deposited by a player
	address[] private _players; // player wallet addresses	
	uint256[] private _accruals; // accruals - used for calculating the winner		

	mapping (address => uint256) private deposits;

	event Winner(uint256 draw, address account, uint256 amount);
	event LiquidityGenerated(uint tokenAmt, uint avaxAmt, uint liquidity);

	constructor(
		uint256 maxPlayerCount, 
		address nekoAddr, 
		address wavaxAddr, 
		address routerAddr
	) 
	{
		maxPlayers = maxPlayerCount;
		token = Neko(nekoAddr);
		wavax = IWAVAX(wavaxAddr);
		router = IPangolinRouter(routerAddr);
		_drawNo.increment();		
	}

    receive() 
    external payable 
    {              
        require(msg.data.length == 0);                        
    }

    fallback()
    external payable
    {    	
    }        

	function isFull()
	external view
	returns (bool)
	{
		return !(_playerCount < maxPlayers);
	}

	function drawNo()
	external view
	returns (uint256)
	{
		return _drawNo.current();
	}

	function depositOf(address player)
	external view
	returns (uint256)
	{
		return deposits[player];
	}

	function maxAmount()
	external view
	returns (uint256)
	{
		return _maxAmount;
	}

	function totalAmount()
	external view
	returns (uint256)
	{
		return _totalAmount;
	}

	function playerCount()
	external view
	returns (uint256)
	{
		return _playerCount;
	}

	function buyIn(uint256 amount)
	external 
	{	
		require(amount > 0);
		require(_playerCount < maxPlayers);	
		if (amount > _maxAmount) {
			_maxAmount = amount;
		}
		_players.push(msg.sender);
		_accruals.push(_playerCount > 0 ? _accruals[_playerCount-1] + amount : amount);
		_totalAmount = SafeMath.add(_totalAmount, amount);
		_playerCount++;		
		deposits[msg.sender] = amount;
		token.transferFrom(msg.sender, address(this), amount);		
	}	

	function draw(uint256 time)
	external	
	onlyOwner()	
	{			
		require(_playerCount == maxPlayers, "NEKO Lottery: must have a full house");		
		uint256 r = _random(time);		
		uint256 prize;
		uint256 residue;
		address winner;		
		for (uint256 i; i < _players.length; i++) {
			uint256 cutoff = _normalize(_accruals[i], _totalAmount, SCALE);			
			if (r < cutoff) {				
				winner = _players[i];
				prize = SafeMath.div(SafeMath.mul(_totalAmount, PRIZE_PART), PRIZE_BASE);
				residue = SafeMath.sub(_totalAmount, prize);
				break;				
			}
		}
		_reset();		
		token.transfer(winner, prize);
		emit Winner(_drawNo.current(), winner, prize);
	}

	function placeLiquidity(uint256 deadlineOffset)
	external
	onlyOwner()
	{		
		uint256 balance = token.balanceOf(address(this));
		require(balance > 0, "NEKO Lottery: must have a balance");

		bool approved = token.approve(address(router), balance);
		require(approved, "NEKO Lottery: PangolinRouter approval failed");		

		uint256 half = SafeMath.div(balance, 2);		
		uint256 deadline = block.timestamp + deadlineOffset;
		_swap(half, deadline);
 		_addLiquidity(deadline); 
 		// whatever remains after 
 		uint256 change = token.balanceOf(address(this));
 		token.transfer(msg.sender, change); 		
	}

	function _swap(uint256 amount, uint256 deadline)
	private	
	{		
		address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(wavax);                   
 		router.swapExactTokensForAVAX(amount, 0, path, address(this), deadline);		
	}

	function _addLiquidity(uint256 deadline) 
	private	
	{
 		uint256 tokenBalance = token.balanceOf(address(this));
 		uint256 wavaxBalance = address(this).balance; 		
		(uint tokenAmt, uint avaxAmt, uint liq) = router
			.addLiquidityAVAX{value: wavaxBalance}(address(token), tokenBalance, 0, 0, msg.sender, deadline);
		emit LiquidityGenerated(tokenAmt, avaxAmt, liq);
	}

	function _reset() 
	private	
	{		
		_playerCount = 0;
		_totalAmount = 0;
		_maxAmount = 0;
		for (uint256 i; i < _players.length; i++) {	
			deposits[_players[i]] = 0;		
		}
		delete _players;
		delete _accruals;		
		_drawNo.increment();
	}

	function _random(uint256 time) 
	private  
	returns (uint) {
		_randNonce++;
		uint randomHash = uint(keccak256(abi.encodePacked(time, msg.sender, _randNonce)));	    
	    return randomHash % 10**SCALE;
	} 

	function _normalize(uint256 n, uint256 base, uint256 scale)
	private pure 
	returns (uint256)
	{
		uint256 scaled = SafeMath.mul(n, 10**SCALE);
		uint256 normed = SafeMath.div(scaled, base);
		return normed;
	}

}