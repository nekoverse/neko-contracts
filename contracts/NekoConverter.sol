//SPDX-License-Identifier: MIT
pragma solidity >= 0.6.2 < 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IPangolinRouter.sol";

contract NekoConverter is Ownable {    
    
    address private token;
    address private wavax;
    uint256 private deadlineOffset;

    IPangolinRouter public immutable router;

    constructor(
        address tokenAddr, 
        address wavaxAddr, 
        address routerAddr, 
        uint256 offset
    ) 
    {
        token = tokenAddr;
        wavax = wavaxAddr;
        deadlineOffset = offset;
        router = IPangolinRouter(routerAddr);
    }    

    receive() 
    external payable 
    {              
        require(msg.data.length == 0);                                        
                        
        address[] memory path = new address[](2);
        path[0] = wavax;
        path[1] = token;

        uint256 deadline = block.timestamp + deadlineOffset;
        router.swapExactAVAXForTokens{value: msg.value}(0, path, msg.sender, deadline);        
    }

    function buy()
    external payable
    {        
        address[] memory path = new address[](2);
        path[0] = wavax;
        path[1] = token;

        uint256 deadline = block.timestamp + deadlineOffset;
        router.swapExactAVAXForTokens{value: msg.value}(0, path, msg.sender, deadline);        
    }  

    function setOffset(uint256 offset)
    external
    onlyOwner()
    {
        deadlineOffset = offset;
    }
}
