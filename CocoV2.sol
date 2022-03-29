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
    address public marketplace;
    address public proxy;

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
        
        waveCatchers = 0x8039C87E4F5417c467e81974E90d55A40A6877E8;
        cocov1 = 0x562DEa9BE18FbfABfFA28Ac7Ea2Be511C2A2ED9B; 
    }

    function ownerMint(address _user, uint256 amount) external onlyOwner {
        _mint(_user, amount);
    }

    function claimPassiveYield(address _user, uint16[] memory _tokenIds) public {
        require(msg.sender == _user, "please call as token owner");
        uint256 rewards = 0;

        for (uint i = 0; i < _tokenIds.length; i++) {
            uint16 tokenId = _tokenIds[i];
            require(
                ERC721(waveCatchers).ownerOf(tokenId) == _user,
                "You are not the owner of this token"
            );

            rewards += getPassiveRewardsForId(tokenId);
            tokenToLastClaimedPassive[tokenId] = block.timestamp;
        }
        _mint(_user, rewards);
    }

    function claimStakingRewards(address _user, uint16[] memory _tokenIds) public {
        require(msg.sender == _user, "please call as token owner");

        uint256 rewards = 0;

        for (uint i = 0; i < _tokenIds.length; i++) {
            uint16 tokenId = _tokenIds[i];
            require(stakes[_user].contains(tokenId), "u are not the staker or this token isnt staked");
            rewards += getStakedRewardsForId(tokenId);
            tokenToLastClaimedStake[tokenId] = block.timestamp;
        }
        _mint(_user, rewards);
    }
    function stake(address _user, uint16[] memory _tokenIds, uint16[] memory _lockupDays, bool claimPassiveRewardsFirst) external {
        require(msg.sender == _user, "please call as token owner");
        if (claimPassiveRewardsFirst) {
            claimPassiveYield(_user, _tokenIds);
        }
        for(uint i = 0; i < _tokenIds.length; i++) {
            uint16 tokenId = _tokenIds[i];
            require(validLockupPeriodsDays[_lockupDays[i]] > 0, "invalid lockup time frame");
            stakes[_user].add(tokenId);
            stakeDatas[tokenId] = StakeData(block.timestamp + (1 days * _lockupDays[i]), validLockupPeriodsDays[_lockupDays[i]]);
            tokenToLastClaimedStake[tokenId] = block.timestamp;
            ERC721(waveCatchers).safeTransferFrom(_user, address(this), tokenId);
        }
    }
    function unstake(address _user, uint16[] memory _tokenIds, bool claimStakingRewardsFirst) external {
        require(msg.sender == _user, "please call as token owner");
        if (claimStakingRewardsFirst) {
            claimStakingRewards(_user, _tokenIds);
        }
        for(uint i = 0; i < _tokenIds.length; i++) {
            uint16 tokenId = _tokenIds[i];
            require(block.timestamp > stakeDatas[tokenId].unlockedTime, "Token not unlocked yet");
            stakes[_user].remove(tokenId);
            tokenToLastClaimedPassive[tokenId] = 0; //do this to prevent double counting
            ERC721(waveCatchers).safeTransferFrom(address(this), _user, tokenId);
        }
    }


    function claimFromV1(address _user, uint256 amount) external {
        require(msg.sender == _user, "please call as token owner");
        require(block.timestamp < EMISSION_START_TIMESTAMP, "Claims no longer accepted, emissions began");
        ERC20Burnable(cocov1).transferFrom(_user, 0x000000000000000000000000000000000000dEaD, amount);
        _mint(_user, amount);
    }

    function getPassiveRewardsForId(uint16 _id) public view returns (uint) {
        require(ERC721(waveCatchers).ownerOf(_id) != address(this), "Stake not set");
        return (block.timestamp - (tokenToLastClaimedPassive[_id] == 0 ? EMISSION_START_TIMESTAMP : tokenToLastClaimedPassive[_id])) * EMISSION_RATE;
    }

    function getStakedRewardsForId(uint16 _id) public view returns (uint) {
        require(ERC721(waveCatchers).ownerOf(_id) == address(this), "Stake not set");
        return (block.timestamp - tokenToLastClaimedStake[_id]) * stakeDatas[_id].emission;
    }
    function getStakes(address _user) public view returns (uint[] memory) {
        EnumerableSet.UintSet storage userStake = stakes[_user];
        uint256 len = userStake.length();
        uint[] memory result = new uint[](len);
        for(uint256 i = 0; i < userStake.length(); i++) {
            result[i] = userStake.at(i);
        }
        return result;
    }
    //returns staked items, timestamp of unlock and emissions as arrays 
    function getStakeDatas(address _user) public view returns (uint[] memory, uint[] memory, uint[] memory) {

        EnumerableSet.UintSet storage userStake = stakes[_user];
        uint256 len = userStake.length();
        uint[] memory indices = new uint[](len);
        uint[] memory timestamps = new uint[](len);
        uint[] memory emissions = new uint[](len);
        for(uint256 i = 0; i < userStake.length(); i++) {
            uint16 index = uint16(userStake.at(i));
            indices[i] = index;
            timestamps[i] = stakeDatas[index].unlockedTime;
            emissions[i] = stakeDatas[index].emission;
        }
        return (indices, timestamps, emissions);
    }

    function setWaveCatchersAddress(address _address) external onlyOwner {
        waveCatchers = _address;
    }
    function setCocoV1Address(address _address) external onlyOwner {
        cocov1 = _address;
    }
    function setMarketplace(address _address) external onlyOwner {
        marketplace = _address;
    }
    function setProxy(address _address) external onlyOwner {
        proxy = _address;
    }

    function addLockupPeriods(uint16[] memory inDays, uint256[] memory emissions) external onlyOwner {
        for(uint256 i = 0; i < inDays.length; i++) {
            //unchecked: add to set
            validLockupPeriodsDays[inDays[i]] = emissions[i];
        }
    }

     function onERC721Received(
         address,
         address,
         uint256,
         bytes memory
     ) public virtual override returns (bytes4) {
         return this.onERC721Received.selector;
     }


    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        if(spender == marketplace) return uint256(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        return super.allowance(owner, spender);
    }
}
