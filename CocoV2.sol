// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// ._. _________                      
// | | \_   ___ \  ____   ____  ____  
// | | /    \  \/ /  _ \_/ ___\/  _ \ 
//  \| \     \___(  <_> )  \__(  <_> )
//  __  \______  /\____/ \___  >____/ 
//  \/         \/            \/    
// @author WG <https://twitter.com/whalegoddess>   

contract Coco is ERC20Burnable, Ownable, IERC721Receiver {
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public EMISSION_RATE = 1157407407407407;
    uint256 public immutable EMISSION_START_TIMESTAMP;
    address public waveCatchers;
    address public cocov1;

    mapping(uint16 => uint256) validLockupPeriodsDays;

    struct StakeData {
        uint256 unlockedTime;
        uint256 emission;
    }

    mapping(address => EnumerableSet.UintSet) stakes;
    mapping(uint16 => StakeData) stakeDatas;

    mapping (uint16 => uint256) tokenToLastClaimedPassive;
    mapping (uint16 => uint256) tokenToLastClaimedStake;

    constructor() ERC20("Coco", "COCO") {
        EMISSION_START_TIMESTAMP =  block.timestamp;
        /* mainnet addresses
        waveCatchers = 0x1A331c89898C37300CccE1298c62aefD3dFC016c;
        cocov1 = 0x133B7c4A6B3FDb1392411d8AADd5b8B006ad69a4; 
        */
        
        waveCatchers = 0x1A331c89898C37300CccE1298c62aefD3dFC016c;
        cocov1 = 0x000000000000000000000000000000000000dEaD; 
    }

    function claimPassiveYield(uint16[] memory _tokenIds) public {
        uint256 rewards = 0;

        for (uint i = 0; i < _tokenIds.length; i++) {
            uint16 tokenId = _tokenIds[i];
            require(
                ERC721(waveCatchers).ownerOf(tokenId) == msg.sender,
                "You are not the owner of this token"
            );

            rewards += getPassiveRewardsForId(tokenId);
            tokenToLastClaimedPassive[tokenId] = block.timestamp;
        }
        _mint(msg.sender, rewards);
    }

    function claimStakingRewards(uint16[] memory _tokenIds) public {
        uint256 rewards = 0;

        for (uint i = 0; i < _tokenIds.length; i++) {
            uint16 tokenId = _tokenIds[i];
            require(stakes[msg.sender].contains(tokenId), "u are not the staker or this token isnt staked");
            rewards += getStakedRewardsForId(tokenId);
            tokenToLastClaimedStake[tokenId] = block.timestamp;
        }
        _mint(msg.sender, rewards);
    }
    function stake(uint16[] memory _tokenIds, uint16[] memory _lockupDays, bool claimPassiveRewardsFirst) external {
        if (claimPassiveRewardsFirst) {
            claimPassiveYield(_tokenIds);
        }
        for(uint i = 0; i < _tokenIds.length; i++) {
            uint16 tokenId = _tokenIds[i];
            require(validLockupPeriodsDays[_lockupDays[i]] > 0, "invalid lockup time frame");
            stakes[msg.sender].add(tokenId);
            stakeDatas[tokenId] = StakeData(block.timestamp + (1 days * _lockupDays[i]), validLockupPeriodsDays[_lockupDays[i]]);
            tokenToLastClaimedStake[tokenId] = block.timestamp;
            ERC721(waveCatchers).safeTransferFrom(msg.sender, address(this), tokenId);
        }
    }
    function unstake(uint16[] memory _tokenIds, bool claimStakingRewardsFirst) external {
        if (claimStakingRewardsFirst) {
            claimStakingRewards(_tokenIds);
        }
        for(uint i = 0; i < _tokenIds.length; i++) {
            uint16 tokenId = _tokenIds[i];
            require(block.timestamp > stakeDatas[tokenId].unlockedTime, "Token not unlocked yet");
            stakes[msg.sender].remove(tokenId);
            ERC721(waveCatchers).safeTransferFrom(address(this), msg.sender, tokenId);
        }
    }


    function claimFromV1(uint256 amount) external {
        require(block.timestamp < EMISSION_START_TIMESTAMP, "Claims no longer accepted, emissions began");
        ERC20Burnable(cocov1).transferFrom(msg.sender, 0x000000000000000000000000000000000000dEaD, amount);
        _mint(msg.sender, amount);
    }

    function getPassiveRewardsForId(uint16 _id) public view returns (uint) {
        return (block.timestamp - (tokenToLastClaimedPassive[_id] == 0 ? EMISSION_START_TIMESTAMP : tokenToLastClaimedPassive[_id])) * EMISSION_RATE;
    }

    function getStakedRewardsForId(uint16 _id) public view returns (uint) {
        require(ERC721(waveCatchers).ownerOf(_id) == address(this), "Stake not set");
        return (block.timestamp - (tokenToLastClaimedStake[_id] == 0 ? EMISSION_START_TIMESTAMP : tokenToLastClaimedStake[_id])) * stakeDatas[_id].emission;

    }

    function setWaveCatchersAddress(address _address) external onlyOwner {
        waveCatchers = _address;
    }
    function setCocoV1Address(address _address) external onlyOwner {
        cocov1 = _address;
    }

    function addLockupPeriods(uint16[] memory inDays, uint16[] memory emissions) external onlyOwner {
        for(uint256 i = 0; i < inDays.length; i++) {
            //unchecked: add to set
            validLockupPeriodsDays[inDays[i]] = emissions[i];
        }
    }

     function onERC721Received(
         address operator,
         address,
         uint256,
         bytes memory
     ) public virtual override returns (bytes4) {
         return this.onERC721Received.selector;
     }
}
