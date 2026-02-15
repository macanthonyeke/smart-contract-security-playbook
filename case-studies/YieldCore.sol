// SPDX-License-Identifier: MIT
pragma solidity >0.8.18;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldCore is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;

    uint256 public constant MAX_REWARD_TIME = 1 days;
    uint256 public constant DIVISOR = 100;
    uint256 public constant GRACE_PERIOD = 2 days;

    uint256 public rewardPool;

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 lockPeriod;
        uint256 fixedRate;
        uint256 rewardsClaimed;
        bool active;
        bool expired;
    }

    mapping(address => StakeInfo[]) public stakes;
    mapping(uint256 => uint256) public dailyRateByLock;
    mapping(uint256 => uint256) public penaltyByLock;

    event LockParametersUpdated(uint256 lockPeriod, uint256 dailyRate, uint256 penaltyRate);
    event RewardFunded(address indexed owner, uint256 amount);
    event Staked(address indexed user, uint256 stakeIndex, uint256 amount, uint256 lockPeriod);
    event ClaimedReward(address indexed user, uint256 stakeIndex, uint256 reward);
    event UnstakeAfterLock(address indexed user, uint256 stakeIndex, uint256 principal, uint256 reward);
    event EarlyUnstake(address indexed user, uint256 stakeIndex, uint256 principal, uint256 penalty);
    event StakeExpired(address indexed user, uint256 stakeIndex);
    event EmergencyWithdrawal(address indexed user, uint256 stakeIndex, uint256 principal);
    event ExcessRewardsWithdrawn(address indexed owner, uint256 amount);

    constructor(IERC20 _stakingToken) Ownable(msg.sender) {
        stakingToken = _stakingToken;
    }

    function setLockParameters(uint256 _lockPeriod, uint256 _dailyRate, uint256 _penaltyRate)
        external
        onlyOwner
    {
        require(_lockPeriod > 0, "invalid lock period");

        dailyRateByLock[_lockPeriod] = _dailyRate;
        penaltyByLock[_lockPeriod] = _penaltyRate;

        emit LockParametersUpdated(_lockPeriod, _dailyRate, _penaltyRate);
    }

    function _isExpired(StakeInfo memory s) internal view returns (bool) {
        return block.timestamp >= s.startTime + s.lockPeriod + GRACE_PERIOD;
    }

    function fundRewardPool(uint256 _amount) external onlyOwner whenNotPaused {
        require(_amount > 0, "can't deposit zero");

        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        rewardPool += _amount;

        emit RewardFunded(msg.sender, _amount);
    }

    function stake(uint256 _amount, uint256 _lockPeriod) external whenNotPaused {
        require(_amount > 0, "can't stake zero");

        uint256 rate = dailyRateByLock[_lockPeriod];
        require(rate > 0, "invalid lock period");

        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

        stakes[msg.sender].push(
            StakeInfo({
                amount: _amount,
                startTime: block.timestamp,
                lockPeriod: _lockPeriod,
                fixedRate: rate,
                rewardsClaimed: 0,
                active: true,
                expired: false
            })
        );

        emit Staked(msg.sender, stakes[msg.sender].length - 1, _amount, _lockPeriod);
    }

    // so we calculate reward only for those who are active and without expired stake index
    // we cap rewards at 1 day,

    function calculateReward(address _user, uint256 _index) public view returns (uint256) {
        StakeInfo memory s = stakes[_user][_index];

        if (!s.active || s.expired || _isExpired(s)) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - s.startTime;

        if (timeElapsed > MAX_REWARD_TIME) {
            timeElapsed = MAX_REWARD_TIME;
        }

        uint256 totalEarned = (s.amount * s.fixedRate * timeElapsed) / (DIVISOR * 1 days);

        if (totalEarned <= s.rewardsClaimed) {
            return 0;
        } else {
            return totalEarned - s.rewardsClaimed;
        }
    }

    function claimReward(uint256 _index) external whenNotPaused nonReentrant {
        StakeInfo storage s = stakes[msg.sender][_index];
        require(s.active, "inactive stake");

        uint256 reward = calculateReward(msg.sender, _index);
        require(reward > 0, "no accrued rewards");
        require(reward <= rewardPool, "insufficient reward pool");

        s.rewardsClaimed += reward;
        rewardPool -= reward;

        stakingToken.safeTransfer(msg.sender, reward);

        emit ClaimedReward(msg.sender, _index, reward);
    }

    function unstake(uint256 _index) external whenNotPaused nonReentrant {
        StakeInfo storage s = stakes[msg.sender][_index];
        require(s.active || s.expired, "inactive stake");

        uint256 principal = s.amount;
        uint256 reward = 0;
        uint256 payout;
        uint256 penalty = 0;

        if (_isExpired(s)) {
            s.expired = true;
        }

        bool lockExpired = block.timestamp >= s.startTime + s.lockPeriod;

        if (lockExpired) {
            reward = calculateReward(msg.sender, _index);
            require(reward <= rewardPool, "insufficient reward pool balance");

            rewardPool -= reward;
            s.rewardsClaimed += reward;
            payout = principal + reward;
        } else {
            uint256 penaltyPercentage = penaltyByLock[s.lockPeriod];
            penalty = (principal * penaltyPercentage) / DIVISOR;

            rewardPool += penalty;
            payout = s.amount - penalty;
        }

        s.amount = 0;
        s.active = false;

        stakingToken.safeTransfer(msg.sender, payout);

        if (lockExpired) {
            emit UnstakeAfterLock(msg.sender, _index, principal, reward);
        } else {
            emit EarlyUnstake(msg.sender, _index, principal, penalty);
        }
    }

    function cleanUpExpiredStake(address _user, uint256 _index) external onlyOwner {
        StakeInfo storage s = stakes[_user][_index];

        require(s.active, "already inactive");
        require(_isExpired(s), "not expired");

        s.active = false;
        s.expired = true;

        emit StakeExpired(_user, _index);
    }

    function emergencyWithdraw(uint256 _index) external whenPaused nonReentrant {
        StakeInfo storage s = stakes[msg.sender][_index];
        require(s.active, "invalid stake");

        uint256 principal = s.amount;

        s.amount = 0;
        s.active = false;

        stakingToken.safeTransfer(msg.sender, principal);

        emit EmergencyWithdrawal(msg.sender, _index, principal);
    }

    function withdrawExcessRewards() external onlyOwner whenPaused nonReentrant {
        uint256 balance = stakingToken.balanceOf(address(this));
        require(balance > rewardPool, "no excess rewards");

        uint256 excess = balance - rewardPool;

        stakingToken.safeTransfer(owner(), excess);

        emit ExcessRewardsWithdrawn(owner(), excess);
    }

    function maxReward(address _user, uint256 _index) public view returns (uint256) {
        StakeInfo memory s = stakes[_user][_index];

        uint256 rate = s.fixedRate;

        return (s.amount * rate) / 100;
    }

    function getStakeCount(address _user) public view returns (uint256) {
        return stakes[_user].length;
    }

    function getStake(address _user, uint256 _index)
        external
        view
        returns (
            uint256 amount,
            uint256 startTime,
            uint256 lockPeriod,
            uint256 fixedRate,
            uint256 rewardsClaimed,
            bool active,
            bool expired
        )
    {
        StakeInfo memory s = stakes[_user][_index];

        return (s.amount, s.startTime, s.lockPeriod, s.fixedRate, s.rewardsClaimed, s.active, s.expired);
    }

    function getRewardsClaimed(address _user, uint256 _index) external view returns (uint256) {
        return stakes[_user][_index].rewardsClaimed;
    }

    function getContractBalance() public view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
