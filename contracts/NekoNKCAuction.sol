//SPDX-License-Identifier: MIT
pragma solidity >= 0.6.2 < 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "neko/contracts/Neko.sol";
import "./NekoNKC.sol";
import "hardhat/console.sol";

contract NekoNKCAuction is Ownable {

	uint public constant EXP = 6;					// precision exponent
	uint public constant SCALE = 10**EXP;			// precision scale

    NekoNKC public nekoNft;                         // NEKO Lucky ERC721 token reference

    // Current state of the auction.
    bool[] private collected;                                       // tokenId => is collected;
    uint[] private highestBid;                                      // tokenId => highest bid
    address[] private highestBidder;                                // tokenId => highest bidder
    mapping (address => bool) private hasWinningBid;                // wallet address => has a winning bid
    mapping (address => mapping (uint => uint)) private bidSoFar;   // wallet address => tokenId => bid so far

    // Final state of the auction
    uint public residualFunds;                     // funds eligible for collection
    address[] private winner;                       // tokenId => wallet address
    uint[] private winningBid;                      // tokenId => winning bid

    // Allowed withdrawals of previous bids
    mapping(address => uint) private pendingReturns;// wallet address => amount of AVAX redeemable

    bool[] private started;                         // tokenId => has auction for this token started
    bool[] private ended;                           // tokenId => has auction for this token ended

    uint public minBidIncrement;                    // minimum bid increment
    uint public minBid;     						// minimum bid price
    uint public prizePct;							// percent of initial sum that will go into the prize pool
    bool public paused;                             // is auction paused

    // Events that will be emitted on changes.
    event HighestBidIncreased(uint tokenId, address bidder, uint amount);
    event Withdrawal(address bidder, uint amount);
    event AuctionStarted(uint tokenId);
    event AuctionEnded(uint tokenId, address winner, uint amount);

    constructor(address nekoNftAddr)
    {
        nekoNft = NekoNKC(payable(nekoNftAddr));

        uint maxTokens = nekoNft.maxTokens();

        collected = new bool[](maxTokens);
        highestBid = new uint[](maxTokens);
        highestBidder = new address[](maxTokens);

        winner = new address[](maxTokens);
        winningBid = new uint[](maxTokens);

        started = new bool[](maxTokens);
        ended = new bool[](maxTokens);
    }

    /// Bid on the auction with the value sent
    /// together with this transaction.
    /// The value will only be refunded if the
    /// auction is not won.
    function bidTopUp(uint tokenId)
    external payable
    {
        require(started[tokenId] && !ended[tokenId], "NEKO Auction: auction must be in progress");
        require(!paused, "NEKO Auction: auction must not be paused");

        uint bid = msg.value + bidSoFar[msg.sender][tokenId];
        require(bid >= minBid, "NEKO Auction: bid must be higher than minimum level");
        require(bid >= highestBid[tokenId] + minBidIncrement, "NEKO Auction: bid increment must exceed highest bud + min increment");
        require(highestBidder[tokenId] != msg.sender, "NEKO Auction: can't top up your own winning bid");

        // only allow one winning bid at a time - this ensures only one wallet per NFT
        require(!hasWinningBid[msg.sender], "NEKO Auction: other bid is currently winning");

        // the previous bid is no longer highest, add it to pending withdrawals
        if (highestBid[tokenId] != 0) {
            pendingReturns[highestBidder[tokenId]] += highestBid[tokenId];
            hasWinningBid[highestBidder[tokenId]] = false;
        }

        // the sender's bid is now winning, remove the previous unsuccessful bid from pending withdrawals
        if (bidSoFar[msg.sender][tokenId] != 0)
            pendingReturns[msg.sender] -= bidSoFar[msg.sender][tokenId];

        highestBidder[tokenId] = msg.sender;
        highestBid[tokenId] = bid;
        bidSoFar[msg.sender][tokenId] = bid;
        hasWinningBid[msg.sender] = true;

        emit HighestBidIncreased(tokenId, msg.sender, bid);
    }

    /// Withdraw all your bids that were overbid.
    function withdraw()
    external
    {
        require(!paused, "NEKO Auction: auction must not be paused");

        uint amount = pendingReturns[msg.sender];
        if (amount > 0) {
            pendingReturns[msg.sender] = 0;

            // need to clear bidSoFar on anything that is not winning
            uint maxTokens = nekoNft.maxTokens();
            for (uint tokenId = 0; tokenId < maxTokens; tokenId++) {
                if (started[tokenId] && !ended[tokenId] && highestBidder[tokenId] != msg.sender) {
                    bidSoFar[msg.sender][tokenId] = 0;
                }
            }

            bool success = payable(msg.sender).send(amount);
            require(success, "NEKO Auction: withdrawal failed");
            emit Withdrawal(msg.sender, amount);
        }
    }

    /// Mint and collect your winning NFT
    function collect(uint tokenId)
    external
    {
        require(ended[tokenId], "NEKO Auction: auction must have ended");
        require(!collected[tokenId], "NEKO Auction: item has already been collected");
        require(winner[tokenId] == msg.sender, "NEKO Auction: you are not the winner");
        collected[tokenId] = true;
        uint mintValue = SafeMath.div(SafeMath.mul(winningBid[tokenId], prizePct), SCALE);
        uint residualValue = SafeMath.sub(winningBid[tokenId], mintValue);
        nekoNft.mint{value: mintValue}(tokenId, msg.sender);
    }

    // only owner

    /// Start auction for token range
    function start(uint start, uint end)
    external
    onlyOwner()
    {
        require(prizePct > 0, "NEKO Auction: prize percent needs to be >0");
        require(minBid > 0, "NEKO Auction: minimum bid needs to be >0");
        require(minBidIncrement > 0, "NEKO Auction: minimum bid increment needs to be >0");
        for (uint tokenId = start; tokenId < end; tokenId++) {
            require(!started[tokenId] && !ended[tokenId], "NEKO Auction: must be unstarted and unended");
            started[tokenId] = true;
            emit AuctionStarted(tokenId);
        }
    }

    /// End auction for token range
    function end(uint start, uint end)
    external
    onlyOwner()
    {
        for (uint i = start; i < end; i++) {
            require(started[i] && !ended[i], "NEKO Auction: must be started and not ended");
            ended[i] = true;
            winner[i] = highestBidder[i];
            winningBid[i] = highestBid[i];

            emit AuctionEnded(i, winner[i], winningBid[i]);
            uint mintValue = SafeMath.div(SafeMath.mul(winningBid[i], prizePct), SCALE);
            uint residualValue = SafeMath.sub(winningBid[i], mintValue);
            residualFunds = SafeMath.add(residualFunds, residualValue);
            nekoNft.assignMintOwner(i, winner[i], mintValue);
        }
    }

    function claimFunds()
    external
    onlyOwner()
    {
        uint funds = residualFunds;
        residualFunds = 0;
        bool success = payable(msg.sender).send(funds);
        // (bool sent, bytes memory data) = msg.sender.call{value: funds}("");
        require(success, "NEKO Auction: claim succeeded");
    }

    function pause()
    external
    onlyOwner()
    {
        paused = true;
    }

    function unpause()
    external
    onlyOwner()
    {
        paused = false;
    }

    function setPrizePct(uint pct)
    external
    onlyOwner()
    {
        require(pct >= 0 && pct <= SCALE, "NEKO Lucky NFT: must be between 0 and 1000000, inclusive");
        prizePct = pct;
    }

    function setMinBid(uint _min)
    external
    onlyOwner()
    {
        minBid = _min;
    }

    function setMinBidIncrement(uint _increment)
    external
    onlyOwner()
    {
        minBidIncrement = _increment;
    }

    // views

    function isCollected(uint tokenId)
    external view
    returns (bool)
    {
        return collected[tokenId];
    }

    function highestBidOn(uint tokenId)
    external view
    returns (uint)
    {
        return highestBid[tokenId];
    }

    function winnerOf(uint tokenId)
    external view
    returns (address)
    {
        return winner[tokenId];
    }

    function bidOf(address bidder, uint tokenId)
    external view
    returns (uint)
    {
        return bidSoFar[bidder][tokenId];
    }

}