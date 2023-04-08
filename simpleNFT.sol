// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
 
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MIT is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor() ERC721("MIT-nft", "MIT") {
        
    }

    function createToken(string memory tokenURI) public onlyOwner returns(uint) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);
        return newItemId;
    }

    function approveMarketplace(address contractAddress) public onlyOwner returns(bool) {
        setApprovalForAll(contractAddress, true);
        return true;
    }
}