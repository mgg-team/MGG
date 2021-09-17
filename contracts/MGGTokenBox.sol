// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IMintableERC20} from "./interface/IMintableERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";

///
/// @dev A contract which allows HOE owner to claim their MGG every week
///

contract MGGTokenBox is ReentrancyGuard {
  using SafeMath for uint256;

  event PendingGovernanceUpdated(
    address pendingGovernance
  );

  event GovernanceUpdated(
    address governance
  );

  event RewardRateUpdated(
    uint256 rewardRate
  );

  event TokensClaimed(
    address indexed user,
    uint256 week,
    uint256 hoeId,
    uint256 amount
  );

  /// @dev The token which will be minted as a reward for staking.
  IMintableERC20 public reward;

  IERC721Enumerable public hoeContract;

  /// @dev The address of the account which currently has administrative capabilities over this contract.
  address public governance;

  address public pendingGovernance;

  uint256 private constant SECONDS_PER_WEEK = 604800; /* 86400 seconds in a day , 604800 seconds in a week */

  // Track claimed tokens by week
  // IMPORTANT: The format of the mapping is:
  // weekClaimedByTokenId[week][tokenId][claimed]

  mapping(uint256 => mapping(uint256 => bool)) public weekClaimedByTokenId;

  uint256 private _startTimestamp;

  uint256 public tokenIdStart = 0;
  uint256 public tokenIdEnd = 9999;

  uint256 public rewardPerHOEPerWeek;


  constructor(
    IMintableERC20 _reward,
    address _hoeContractAddress,
    uint256 startTimestamp_,
    uint256 _rewardPerHOEPerWeek,
    address _governance
  ) public {
    require(_governance != address(0), "MGGTokenBox: governance address cannot be 0x0");

    reward = _reward;
    hoeContract = IERC721Enumerable(_hoeContractAddress);
    _startTimestamp = startTimestamp_;
    rewardPerHOEPerWeek = _rewardPerHOEPerWeek;
    governance = _governance;
  }

  /// @dev A modifier which reverts when the caller is not the governance.
  modifier onlyGovernance() {
    require(msg.sender == governance, "MGGTokenBox: only governance");
    _;
  }

  /// @dev Sets the governance.
  ///
  /// This function can only called by the current governance.
  ///
  /// @param _pendingGovernance the new pending governance.
  function setPendingGovernance(address _pendingGovernance) external onlyGovernance {
    require(_pendingGovernance != address(0), "MGGTokenBox: pending governance address cannot be 0x0");
    pendingGovernance = _pendingGovernance;

    emit PendingGovernanceUpdated(_pendingGovernance);
  }

  function acceptGovernance() external {
    require(msg.sender == pendingGovernance, "MGGTokenBox: only pending governance");

    address _pendingGovernance = pendingGovernance;
    governance = _pendingGovernance;

    emit GovernanceUpdated(_pendingGovernance);
  }

  function updateRewardRate(uint256 rewardRate) external onlyGovernance {
    rewardPerHOEPerWeek = rewardRate;
    emit RewardRateUpdated(rewardRate);
  }

  function currentWeek() public view returns (uint256 weekNumber) {
      return uint256(block.timestamp / SECONDS_PER_WEEK);
  }

  function startWeek()public view returns (uint256 weekNumber) {
      return uint256(_startTimestamp / SECONDS_PER_WEEK);
  }

  function getClaimStatus(uint256 week, uint256 tokenId)public view returns (bool claimed) {
      return weekClaimedByTokenId[week][tokenId];
  }

  /// @notice Claim MGG for a given HOE ID
  /// @param tokenId The tokenId of the HOE NFT
  function claimById(uint256 tokenId, uint256 week) external nonReentrant{

      // Check that the msgSender owns the token that is being claimed
      require(
          msg.sender == hoeContract.ownerOf(tokenId),
          "MUST_OWN_TOKEN_ID"
      );

      require(
          !weekClaimedByTokenId[week][tokenId],
          "Already Claimed"
      );

      // Further Checks, Effects, and Interactions are contained within the
      // _claim() function
      _claim(tokenId, msg.sender, week);
  }

    /// @notice Claim MGG for all tokens owned by the sender
    /// @notice This function will run out of gas if you have too much HOE!
    function claimAllForOwner(uint256 week) external {
        uint256 tokenBalanceOwner = hoeContract.balanceOf(msg.sender);

        // Checks
        require(tokenBalanceOwner > 0, "NO_TOKENS_OWNED");

        // i < tokenBalanceOwner because tokenBalanceOwner is 1-indexed
        for (uint256 i = 0; i < tokenBalanceOwner; i++) {
            // Further Checks, Effects, and Interactions are contained within
            // the _claim() function

            if(!weekClaimedByTokenId[week][hoeContract.tokenOfOwnerByIndex(msg.sender, i)]){
              _claim(
                  hoeContract.tokenOfOwnerByIndex(msg.sender, i),
                  msg.sender,
                  week
              );
            }
        }
    }

    /// @dev Internal function to mint MGG upon claiming
    function _claim(uint256 tokenId, address tokenOwner, uint256 week) internal {
        // Checks
        // Check that the token ID is in range
        // We use >= and <= to here because all of the token IDs are 0-indexed
        require(
            tokenId >= tokenIdStart && tokenId <= tokenIdEnd,
            "TOKEN_ID_OUT_OF_RANGE"
        );

        require(
            week >= startWeek() && week <= currentWeek(),
            "Need Valid Week"
        );

        // Check that MGG have not already been claimed this week
        // for a given tokenId
        require(
            !weekClaimedByTokenId[week][tokenId],
            "Already Claimed"
        );

        // Mark that MGG has been claimed for this week for the
        // given tokenId
        weekClaimedByTokenId[week][tokenId] = true;



        // Send MGG to the owner of the token ID
        reward.mint(tokenOwner, rewardPerHOEPerWeek);
    }

}
