// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "hardhat/console.sol";

contract NFTMarket is ReentrancyGuard,VRFConsumerBase {

  bytes32 internal keyHash;
  uint256 internal fee;
    
  uint256 public randomResult;


  using Counters for Counters.Counter;

  Counters.Counter private _tradeItemIds;
  Counters.Counter private _NftItemId;

  address payable owner;

  constructor() VRFConsumerBase(
            0x8C7382F9D8f56b33781fE506E897a4F1e2d17255, // VRF Coordinator
            	0x326C977E6efc84E512bB9C30f76E30c160eD06FB  // LINK Token
        ) {
    owner = payable(msg.sender);
    
    
        keyHash = 0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4;
        fee = 0.0001 * 10 ** 18; // 0.1 LINK (Varies by network)
    
  }

  function getRandomNumber() internal returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK - fill contract with faucet");
        return requestRandomness(keyHash, fee);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomResult = randomness;
    }

    function callKeccak256(uint256 data) internal view returns(bytes32){
      return bytes32(keccak256(abi.encodePacked(block.timestamp,
                                          msg.sender,
                                          data))) ;
                                          
   } 

//trade item struct 
  struct TradeItem {
      uint256 tradeItemId;
      bytes32 hash;
      uint256 item1;
      uint256 item2;
      address creator;
      address participant;
      bool isActive;
      bool isComplete;
  }

//single NFT struct
  struct NftItem {
    uint256 NftItemId;
    address nftContract;
    uint256 tokenId;
    string tokenURI;
    address payable seller;
    address payable owner;
    bool isApprovedByTrader;
    bool isActive;
  }

  mapping(uint256 => TradeItem) private idToTradeItem;
  mapping(bytes32 => uint256) private hashToTradeItem;
  mapping(uint256 => NftItem) private idToNft;
  mapping(address => uint256) private TradeItemCreatorCount;
  mapping(address => uint256) private TradeItemParticipantCount;

  function createNftItem(
    address nftContract,
    uint256 tokenId
    ) internal returns (uint256) {

      IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
      string memory tokenURI  = IERC721Metadata(nftContract).tokenURI(tokenId);

      _NftItemId.increment();
      uint256 NftItemId = _NftItemId.current();

      idToNft[NftItemId] = NftItem(
        NftItemId,
        nftContract,
        tokenId,
        tokenURI,
        payable(msg.sender),
        payable(address(0)),
        false,
        true
      );
      

      return NftItemId;
    }

//to create initial trade item with 1 nft
  function createTradeItemWith1Nft(
    address nftContract,
    uint256 tokenId
  ) public nonReentrant {
    _tradeItemIds.increment();
    uint256 tradeItemId = _tradeItemIds.current();
    // getRandomNumber();
    bytes32 hash = callKeccak256(tradeItemId);
    idToTradeItem[tradeItemId] = TradeItem(
      tradeItemId,
      hash,
      createNftItem(nftContract,tokenId),
      0,
      msg.sender,
      address(0),
      true,
      false
    );

    hashToTradeItem[hash] = tradeItemId;
    TradeItemCreatorCount[msg.sender]++;
}

  function addNft(
    uint256 tradeItemId,
    address nftContract,
    uint256 tokenId
  ) public nonReentrant {
    if(msg.sender == idToTradeItem[tradeItemId].creator){
      if(idToTradeItem[tradeItemId].item1==0)
      idToTradeItem[tradeItemId].item1 = createNftItem(nftContract,tokenId);
    }
    else if(_tradeItemIds.current() >= tradeItemId && idToTradeItem[tradeItemId].isActive == true && idToTradeItem[tradeItemId].item2==0) {
      idToTradeItem[tradeItemId].item2 = createNftItem(nftContract,tokenId);
      idToTradeItem[tradeItemId].participant = msg.sender;
      TradeItemParticipantCount[msg.sender]++;
    }
    else
    revert("ERROR: NFT not added");
    
  }

  function proceedTrade(
    uint256 tradeItemId
  ) internal nonReentrant {
    address creator = idToTradeItem[tradeItemId].creator;
    address participant = idToTradeItem[tradeItemId].participant; 
    uint256 Item1TokenId = idToNft[idToTradeItem[tradeItemId].item1].tokenId;
    address Item1Contract = idToNft[idToTradeItem[tradeItemId].item1].nftContract;

    uint256 Item2TokenId = idToNft[idToTradeItem[tradeItemId].item2].tokenId;
    address Item2Contract = idToNft[idToTradeItem[tradeItemId].item2].nftContract;

    IERC721(Item1Contract).transferFrom(address(this), participant, Item1TokenId);
    IERC721(Item2Contract).transferFrom(address(this), creator, Item2TokenId);
  }

  function approveNft(
    uint256 tradeItemId,
    uint256 nftNo
  ) public {
     if (msg.sender == idToNft[nftNo].seller)
        revert("Trader cannot approve his own NFT for trade.");
     else if(!(idToTradeItem[tradeItemId].isActive || idToNft[nftNo].isActive)) {
        revert("This trade or nft item is not active at the moment");
     }
     else if(!(idToTradeItem[tradeItemId].item1==nftNo || idToTradeItem[tradeItemId].item2==nftNo))
        revert("This trade item does not contain this nft token");
     else if(!(msg.sender == idToTradeItem[tradeItemId].participant || msg.sender == idToTradeItem[tradeItemId].creator)) {
        revert("This trade cannot be approved by you");
     }
     else{
        idToNft[nftNo].isApprovedByTrader = true;
     }

     if(idToNft[idToTradeItem[tradeItemId].item1].isApprovedByTrader && idToNft[idToTradeItem[tradeItemId].item2].isApprovedByTrader && idToTradeItem[tradeItemId].isActive && idToNft[idToTradeItem[tradeItemId].item1].isActive && idToNft[idToTradeItem[tradeItemId].item2].isActive){
        proceedTrade(tradeItemId);
        idToTradeItem[tradeItemId].isActive = false;
     }
        
  }

  function removeNft(
    uint256 tradeItemId
  ) public {
    if(idToTradeItem[tradeItemId].creator == msg.sender) {
      uint256 nftNo = idToTradeItem[tradeItemId].item1;
      IERC721(idToNft[nftNo].nftContract).transferFrom(address(this), msg.sender, idToNft[nftNo].tokenId);
      idToNft[nftNo].isActive = false;
      idToTradeItem[tradeItemId].item1=0;
    }
    else if(idToTradeItem[tradeItemId].participant == msg.sender ) {
      uint256 nftNo = idToTradeItem[tradeItemId].item2;
      IERC721(idToNft[nftNo].nftContract).transferFrom(address(this), msg.sender, idToNft[nftNo].tokenId);
      idToNft[nftNo].isActive = false;
      TradeItemParticipantCount[msg.sender]--;
      idToTradeItem[tradeItemId].item2=0;
    }
    else 
    revert("ERROR: NO NFT IS REMOVED");
  }


  function deleteTradeItem(
    uint256 tradeItemId
  ) public {
    if(idToTradeItem[tradeItemId].creator == msg.sender && _tradeItemIds.current()>=tradeItemId) {
      idToTradeItem[tradeItemId].isActive = false;
      TradeItemCreatorCount[msg.sender]--;
      if(idToTradeItem[tradeItemId].item2 != 0 ) {
        IERC721(idToNft[idToTradeItem[tradeItemId].item2].nftContract).transferFrom(address(this), idToTradeItem[tradeItemId].participant, idToNft[idToTradeItem[tradeItemId].item2].tokenId);
        idToNft[idToTradeItem[tradeItemId].item2].isActive = false;
      }

      if(idToTradeItem[tradeItemId].item1 != 0 ) {
        IERC721(idToNft[idToTradeItem[tradeItemId].item1].nftContract).transferFrom(address(this), idToTradeItem[tradeItemId].creator, idToNft[idToTradeItem[tradeItemId].item1].tokenId);
        idToNft[idToTradeItem[tradeItemId].item1].isActive = false;
      }
    }
    else 
    revert("ERROR: TRADE DOES NOT EXIST YOU ARE NOT CREATOR OF THIS TRADE");
  }

  function getListedNfts() public view returns (NftItem[] memory) {
    uint totalItemCount = _NftItemId.current();
    uint nftCount=0;
    uint currentIndex = 0;
    for(uint i=0; i<totalItemCount; i++) {
      if(idToNft[i+1].seller == msg.sender && idToNft[i+1].isActive) {
        nftCount = nftCount + 1;
      }
    }
    NftItem[] memory items = new NftItem[](nftCount);
    for (uint i = 0; i < totalItemCount; i++) {
      if (idToNft[i + 1].seller == msg.sender && idToNft[i + 1].isActive) {
        uint currentId = i + 1;
        NftItem storage currentItem = idToNft[currentId];
        items[currentIndex] = currentItem;
        currentIndex += 1;
      }
    }
    return items;
  }

  function getNftItem(uint256 nftNo) public view returns (NftItem memory) {
    return idToNft[nftNo];
  }

  struct TradeItemDTO {
      uint256 tradeItemId;
      bytes32 hash;
      NftItem item1;
      NftItem item2;
      address creator;
      address participant;
      bool isActive;
      bool isComplete;
  }


  function getTradeItem(bytes32 hash) public view returns (TradeItemDTO memory) {
    uint256 No = hashToTradeItem[hash];
    TradeItem memory tempItem = idToTradeItem[No];
    NftItem storage i1 = idToNft[tempItem.item1];
    NftItem storage i2 = idToNft[tempItem.item2];
    TradeItemDTO memory currentItem = TradeItemDTO(tempItem.tradeItemId,tempItem.hash,i1,i2,tempItem.creator,tempItem.participant,tempItem.isActive,tempItem.isComplete);
    return currentItem;
  }


  function getActiveTradesCreated() public view returns (TradeItemDTO[] memory) {
    uint totalItemCount = _tradeItemIds.current();
    uint tradeCount=TradeItemCreatorCount[msg.sender];
    uint currentIndex = 0;

    if(tradeCount==0) {
      revert("ERROR: NO TRADE ITEM AVAILABLE");
    }

    TradeItemDTO[] memory items = new TradeItemDTO[](tradeCount);
    for (uint i = 0; i < totalItemCount; i++) {
      if (idToTradeItem[i + 1].creator == msg.sender && idToTradeItem[i + 1].isActive) {
        uint currentId = i + 1;
        TradeItem memory tempItem = idToTradeItem[currentId];
        NftItem storage i1 = idToNft[tempItem.item1];
        NftItem storage i2 = idToNft[tempItem.item2];
        TradeItemDTO memory currentItem = TradeItemDTO(tempItem.tradeItemId,tempItem.hash,i1,i2,tempItem.creator,tempItem.participant,tempItem.isActive,tempItem.isComplete);
        items[currentIndex] = currentItem;
        currentIndex += 1;
      }
    }
    return items;

  }

  function getActiveTradesParticipated() public view returns (TradeItemDTO[] memory) {
    uint totalItemCount = _tradeItemIds.current();
    uint tradeCount= TradeItemParticipantCount[msg.sender];
    uint currentIndex = 0;

    if(tradeCount==0) {
      revert("ERROR: NO TRADE ITEM Participated AVAILABLE");
    }

    TradeItemDTO[] memory items = new TradeItemDTO[](tradeCount);
    for (uint i = 0; i < totalItemCount; i++) {
      if((idToTradeItem[i+1].participant == msg.sender) && idToTradeItem[i+1].isActive) {
        uint currentId = i + 1;
        TradeItem memory tempItem = idToTradeItem[currentId];
        NftItem storage i1 = idToNft[tempItem.item1];
        NftItem storage i2 = idToNft[tempItem.item2];
        TradeItemDTO memory currentItem = TradeItemDTO(tempItem.tradeItemId,tempItem.hash,i1,i2,tempItem.creator,tempItem.participant,tempItem.isActive,tempItem.isComplete);
        items[currentIndex] = currentItem;
        currentIndex += 1;
      }
    }
    return items;

  }

}