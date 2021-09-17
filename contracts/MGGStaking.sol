pragma solidity 0.6.12;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IMintableERC20} from "./interface/IMintableERC20.sol";

contract MGGStaking is ReentrancyGuard{

    using SafeMath for uint256;
    using SafeERC20 for IMintableERC20;

    struct UserInfo {
        uint256 amount;     // How many mgg tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    IMintableERC20 public mggToken;

    address public collector;

    /// @dev The address of the account which currently has administrative capabilities over this contract.
    address public governance;
    address public pendingGovernance;
    /// @dev A flag indicating if the contract has been initialized yet.
    bool public initialized;

    uint256 public mggRewardRate;
    uint256 lastRewardBlock; //Last block number that mgg distribution occurs.
    uint256 private _accMGGRewardPerBalance;
    uint256 public totalDeposited;

    mapping (address => UserInfo) userInfo;


    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event PendingGovernanceUpdated(address pendingGovernance);
    event GovernanceUpdated(address governance);
    event CollectorUpdated(address collector);
    event RewardClaimed(address indexed user, uint256 amount);
    event MGGRewardRateUpdated(uint256 rewardRate);

    // solium-disable-next-line
    constructor(address _governance) public {
        require(_governance != address(0), "MGGStaking: governance address cannot be 0x0");
        governance = _governance;
    }

    /*
     * Owner methods
     */
    function initialize(address _mggToken,
                        uint256 _mggRewardRate,
                        address _collector) external onlyGovernance {
        require(!initialized, "MGGStaking: already initialized");
        require(_collector != address(0), "MGGStaking: collector address cannot be 0x0");

        mggToken = IMintableERC20(_mggToken);
        mggRewardRate = _mggRewardRate;

        collector = _collector;
        initialized = true;
        lastRewardBlock = block.number;
    }

    /// @dev Checks that the contract is in an initialized state.
    ///
    /// This is used over a modifier to reduce the size of the contract
    modifier expectInitialized() {
        require(initialized, "MGGStaking: not initialized.");
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "MGGStaking: only governance");
        _;
    }

    /// @dev Sets the governance.
    ///
    /// This function can only called by the current governance.
    ///
    /// @param _pendingGovernance the new pending governance.
    function setPendingGovernance(address _pendingGovernance) external onlyGovernance {
        require(_pendingGovernance != address(0), "MGGStaking: pending governance address cannot be 0x0");
        pendingGovernance = _pendingGovernance;

        emit PendingGovernanceUpdated(_pendingGovernance);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "MGGStaking: only pending governance");

        address _pendingGovernance = pendingGovernance;
        governance = _pendingGovernance;

        emit GovernanceUpdated(_pendingGovernance);
    }

    /// @dev Sets the address of the collector
    ///
    /// @param _collector address of the new collector
    function setCollector(address _collector) external onlyGovernance {
        require(_collector != address(0), "MGGStaking: collector address cannot be 0x0.");
        collector = _collector;
        emit CollectorUpdated(_collector);
    }

    function setMGGRewardRate(uint256 _mggRewardRate) external onlyGovernance {
        collectReward();
        mggRewardRate = _mggRewardRate;
        emit MGGRewardRateUpdated(_mggRewardRate);
    }


    function deposit(uint256 _amount) external nonReentrant expectInitialized claimReward(msg.sender){
        UserInfo storage user = userInfo[msg.sender];

        if (_amount > 0) {
            mggToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            totalDeposited = totalDeposited.add(_amount);
        }

        emit Deposit(msg.sender, _amount);
    }


    function withdraw(uint256 amount) external nonReentrant expectInitialized{
      _withdraw(amount);
    }

    function _withdraw(uint256 amount) internal claimReward(msg.sender) {

        UserInfo storage user = userInfo[msg.sender];

        require(amount <= user.amount, "MGGStaking: withdraw too much");

        totalDeposited = totalDeposited.sub(amount);
        user.amount = user.amount - amount;

        mggToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    // solium-disable-next-line no-empty-blocks
    function claim() external expectInitialized nonReentrant claimReward(msg.sender) {
    }

     // Return block rewards over the given _from (inclusive) to _to (inclusive) block.
    function getBlockReward(uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 to = _to;
        uint256 from = _from;

        if (from > to) {
            return 0;
        }

        uint256 rewardPerBlock = mggRewardRate;
        uint256 totalRewards = (to.sub(from)).mul(rewardPerBlock);

        return totalRewards;
    }

    function collectReward() public expectInitialized {
        if (block.number <= lastRewardBlock) {
            return;
        }

        if (totalDeposited == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 mggReward = getBlockReward(lastRewardBlock, block.number);
        mggToken.mint(address(this), mggReward);
        _accMGGRewardPerBalance = _accMGGRewardPerBalance.add(mggReward.mul(1e18).div(totalDeposited));
        lastRewardBlock = block.number;

        uint256 newReward = mggToken.balanceOf(collector);
        if (newReward == 0) {
            return;
        }
        mggToken.transferFrom(collector, address(this), newReward);
        _accMGGRewardPerBalance = _accMGGRewardPerBalance.add(newReward.mul(1e18).div(totalDeposited));
    }

    function pendingReward(address account) public view returns (uint256) {

      UserInfo storage user = userInfo[account];
      uint256 newAccMGGPerBalance = _accMGGRewardPerBalance;
      uint256 pending;

      if(totalDeposited == 0){
        return 0;
      }

      if (user.amount > 0) {
          uint256 newReward = mggToken.balanceOf(collector);
          newAccMGGPerBalance = newAccMGGPerBalance.add(newReward.mul(1e18).div(totalDeposited));
          pending = user.amount.mul(newAccMGGPerBalance).div(1e18).sub(user.rewardDebt);
      }

      if (block.number > lastRewardBlock) {
          uint256 fixedReward = getBlockReward(lastRewardBlock, block.number);

          newAccMGGPerBalance = newAccMGGPerBalance.add(fixedReward.mul(1e18).div(totalDeposited));
          pending = user.amount.mul(newAccMGGPerBalance).div(1e18).sub(user.rewardDebt);
      }

        return pending;
    }

    function userDeposited(address account) public view returns (uint256){
      UserInfo storage user = userInfo[account];
      return user.amount;
    }

    modifier claimReward(address _account) {
        collectReward();
        UserInfo storage user = userInfo[_account];
        uint256 mggPending = 0;
        if (user.amount > 0) {
            mggPending = user.amount.mul(_accMGGRewardPerBalance).div(1e18).sub(user.rewardDebt);
            if (mggPending > 0) {
              _safeMGGTransfer(msg.sender, mggPending);
            }
        }
        _; // user.amount may changed.
        user.rewardDebt = user.amount.mul(_accMGGRewardPerBalance).div(1e18);
        RewardClaimed(_account,mggPending);
    }

    function _safeMGGTransfer(address _to, uint256 _amount) internal {
        if (_amount > 0) {
            uint256 mggBal = mggToken.balanceOf(address(this));
            if (_amount > mggBal) {
                mggToken.transfer(_to, mggBal);
            } else {
                mggToken.transfer(_to, _amount);
            }
        }
    }
}
