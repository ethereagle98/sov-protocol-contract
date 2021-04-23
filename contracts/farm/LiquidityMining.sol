pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

/// SPDX-License-Identifier: MIT

import "../openzeppelin/ERC20.sol";
import "../openzeppelin/SafeERC20.sol";
import "../openzeppelin/SafeMath.sol";
import "../openzeppelin/Ownable.sol";

// MasterChef is the master of RSOV. He can make RSOV and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once RSOV is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract LiquidityMining is Ownable {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	uint256 public constant PRECISION = 1e12;
	// Bonus multiplier for early RSOV makers.
	// During bonus period each passed block will be calculated like N passed blocks, where N = BONUS_MULTIPLIER
	uint256 public constant BONUS_BLOCK_MULTIPLIER = 10;

	//TODO check if we can use uint128 instead of uint256 to save 1 storage slot for each user
	// Info of each user.
	struct UserInfo {
		uint256 amount; // How many LP tokens the user has provided.
		uint256 rewardDebt; // Reward debt. See explanation below.
		//
		// We do some fancy math here. Basically, any point in time, the amount of RSOVs
		// entitled to a user but is pending to be distributed is:
		//
		//   pending reward = (user.amount * pool.accRSOVPerShare) - user.rewardDebt
		//
		// Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
		//   1. The pool's `accRSOVPerShare` (and `lastRewardBlock`) gets updated.
		//   2. User receives the pending reward sent to his/her address.
		//   3. User's `amount` gets updated.
		//   4. User's `rewardDebt` gets updated.
	}

	//TODO probably, we can save slots here, not sure we will have a lot of pools
	// Info of each pool.
	struct PoolInfo {
		IERC20 poolToken; // Address of LP token contract.
		uint256 allocationPoint; // How many allocation points assigned to this pool. RSOVs to distribute per block.
		uint256 lastRewardBlock; // Last block number that RSOVs distribution occurs.
		uint256 accRSOVPerShare; // Accumulated RSOVs per share, times 1e12. See below.
	}

	// The RSOV TOKEN!
	ERC20 public RSOV;
	// RSOV tokens created per block.
	uint256 public RSOVPerBlock;
	// The block number when RSOV mining starts.
	uint256 public startBlock;
	// Block number when bonus RSOV period ends.
	uint256 public bonusEndBlock;

	//TODO check of we still need this array
	// Info of each pool.
	PoolInfo[] public poolInfo;
	// TODO use _lpToken instead of _pid in all functions
	mapping(address => uint256) poolIds;

	// Info of each user that stakes LP tokens.
	mapping(uint256 => mapping(address => UserInfo)) public userInfo;
	// Total allocation points. Must be the sum of all allocation points in all pools.
	uint256 public totalAllocationPoint;

	event PoolTokenAdded(address indexed user, address indexed poolToken, uint256 allocationPoint);
	event PoolTokenUpdated(address indexed user, address indexed poolToken, uint256 newAllocationPoint, uint256 oldAllocationPoint);
	event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
	event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
	event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

	//TODO _startBlock, _bonusEndBlock - start/stop button with updating start and bonus end blocks
	function initialize(
		ERC20 _RSOV,
		uint256 _RSOVPerBlock,
		uint256 _startBlock,
		uint256 _bonusEndBlock
	) public onlyOwner {
		require(address(RSOV) == address(0), "already initialized");
		require(address(_RSOV) != address(0), "token address invalid");

		RSOV = _RSOV;
		RSOVPerBlock = _RSOVPerBlock;
		startBlock = _startBlock;
		bonusEndBlock = _bonusEndBlock;
	}

	// Add a new lp to the pool. Can only be called by the owner.
	function add(uint256 _allocationPoint, address _poolToken, bool _withUpdate) public onlyOwner {
		require(_allocationPoint > 0, "invalid allocation point");
		require(_poolToken != address(0), "invalid token address");
		require(poolIds[_poolToken] == 0, "token already added");

		if (_withUpdate) {
			updateAllPools();
		}

		uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
		totalAllocationPoint = totalAllocationPoint.add(_allocationPoint);

		poolInfo.push(PoolInfo({ poolToken: IERC20(_poolToken), allocationPoint: _allocationPoint, lastRewardBlock: lastRewardBlock, accRSOVPerShare: 0 }));
		//indexing starts from 1 in order to check whether token was already added
		poolIds[_poolToken] = poolInfo.length;

		emit PoolTokenAdded(msg.sender, _poolToken, _allocationPoint);
	}

	// Update the given pool's RSOV allocation point. Can only be called by the owner.
	function update(uint256 _pid, uint256 _allocationPoint, bool _withUpdate) public onlyOwner {
		if (_withUpdate) {
			updateAllPools();
		}

		uint256 previousAllocationPoint = poolInfo[_pid].allocationPoint;
		totalAllocationPoint = totalAllocationPoint.sub(previousAllocationPoint).add(_allocationPoint);
		poolInfo[_pid].allocationPoint = _allocationPoint;

		emit PoolTokenUpdated(user, poolToken, _allocationPoint, previousAllocationPoint);
	}

	// Return reward multiplier over the given _from to _to block.
	function getPassedBlocksWithBonusMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
		if (_to <= bonusEndBlock) {
			return _to.sub(_from).mul(BONUS_BLOCK_MULTIPLIER);
		} else if (_from >= bonusEndBlock) {
			return _to.sub(_from);
		} else {
			return bonusEndBlock.sub(_from).mul(BONUS_BLOCK_MULTIPLIER).add(_to.sub(bonusEndBlock));
		}
	}

	function _pendingRSOV(uint256 _pid, address _user) internal view returns (uint256) {
		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][_user];

		uint256 accRSOVPerShare = pool.accRSOVPerShare;
		uint256 lpSupply = pool.poolToken.balanceOf(address(this));
		if (block.number > pool.lastRewardBlock && lpSupply != 0) {
			uint256 multiplier = getPassedBlocksWithBonusMultiplier(pool.lastRewardBlock, block.number);
			uint256 RSOVReward = multiplier.mul(RSOVPerBlock).mul(pool.allocationPoint).div(totalAllocationPoint);
			accRSOVPerShare = accRSOVPerShare.add(RSOVReward.mul(PRECISION).div(lpSupply));
		}
		return user.amount.mul(accRSOVPerShare).div(PRECISION).sub(user.rewardDebt);
	}

	// View function to see pending RSOVs on frontend.
	function pendingRSOV(uint256 _pid, address _user) external view returns (uint256) {
		return _pendingRSOV(_pid, _user);
	}

	// Update reward variables for all pools. Be careful of gas spending!
	function updateAllPools() public {
		uint256 length = poolInfo.length;
		for (uint256 pid = 0; pid < length; ++pid) {
			updatePool(pid);
		}
	}

	// Update reward variables of the given pool to be up-to-date.
	function updatePool(uint256 _pid) public {
		PoolInfo storage pool = poolInfo[_pid];

		//this pool has been updated recently
		if (block.number <= pool.lastRewardBlock) {
			return;
		}

		uint256 lpSupply = pool.poolToken.balanceOf(address(this));
		if (lpSupply == 0) {
			pool.lastRewardBlock = block.number;
			return;
		}

		uint256 multiplier = getPassedBlocksWithBonusMultiplier(pool.lastRewardBlock, block.number);
		uint256 RSOVReward = multiplier.mul(RSOVPerBlock).mul(pool.allocationPoint).div(totalAllocationPoint);
		//TODO I think we can use RSOV.mint(RSOVReward), but this contract should have an appropriate amount of SOV
		//TODO or as you mentioned this contract should have an appropriate amount of RSOV
		//todo original code minted tokens here, we have to supply tokens to this contract instead
		//RSOV.mint(address(this), RSOVReward);
		pool.accRSOVPerShare = pool.accRSOVPerShare.add(RSOVReward.mul(PRECISION).div(lpSupply));
		pool.lastRewardBlock = block.number;
	}

	// Deposit LP tokens to LiquidityMining for RSOV allocation.
	function deposit(uint256 _pid, uint256 _amount) public {
		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][msg.sender];

		updatePool(_pid);

		if (user.amount > 0) {
			uint256 pending = user.amount.mul(pool.accRSOVPerShare).div(PRECISION).sub(user.rewardDebt);
			_safeRSOVTransfer(msg.sender, pending);
		}
		pool.poolToken.safeTransferFrom(address(msg.sender), address(this), _amount);
		user.amount = user.amount.add(_amount);
		user.rewardDebt = user.amount.mul(pool.accRSOVPerShare).div(PRECISION);
		emit Deposit(msg.sender, _pid, _amount);
	}

	function claimReward(uint256 _pid) public {
		deposit(_pid, 0);
	}

	// Withdraw LP tokens from LiquidityMining.
	function withdraw(uint256 _pid, uint256 _amount) public {
		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][msg.sender];
		require(user.amount >= _amount, "withdraw: not good");

		updatePool(_pid);

		uint256 pending = user.amount.mul(pool.accRSOVPerShare).div(PRECISION).sub(user.rewardDebt);
		_safeRSOVTransfer(msg.sender, pending);
		user.amount = user.amount.sub(_amount);
		user.rewardDebt = user.amount.mul(pool.accRSOVPerShare).div(PRECISION);

		pool.poolToken.safeTransfer(address(msg.sender), _amount);
		emit Withdraw(msg.sender, _pid, _amount);
	}

	// Withdraw without caring about rewards. EMERGENCY ONLY.
	function emergencyWithdraw(uint256 _pid) public {
		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][msg.sender];

		pool.poolToken.safeTransfer(address(msg.sender), user.amount);
		emit EmergencyWithdraw(msg.sender, _pid, user.amount);
		user.amount = 0;
		user.rewardDebt = 0;
	}

	// Safe RSOV transfer function, just in case if rounding error causes pool to not have enough RSOVs.
	function _safeRSOVTransfer(address _to, uint256 _amount) internal {
		uint256 RSOVBal = RSOV.balanceOf(address(this));
		if (_amount > RSOVBal) {
			_amount = RSOVBal;
		}
		require(RSOV.transfer(_to, _amount), "transfer failed");
	}

	// Custom logic - helpers

	function getPoolLength() external view returns (uint256) {
		return poolInfo.length;
	}

	function getPoolInfos() external view returns (PoolInfo[] memory poolInfos) {
		return poolInfo;
	}

	function getOptimisedUserInfos(address _user) external view returns (uint256[2][] memory userInfos) {
		uint256 length = poolInfo.length;
		userInfos = new uint256[2][](length);
		for (uint256 pid = 0; pid < length; ++pid) {
			userInfos[pid][0] = userInfo[pid][_user].amount;
			userInfos[pid][1] = _pendingRSOV(pid, _user);
		}
	}

	function getUserInfos(address _wallet) external view returns (UserInfo[] memory userInfos) {
		uint256 length = poolInfo.length;
		userInfos = new UserInfo[](length);
		for (uint256 pid = 0; pid < length; ++pid) {
			userInfos[pid] = userInfo[pid][_wallet];
		}
	}

	function getPendingRSOV(address _user) external view returns (uint256[] memory pending) {
		uint256 length = poolInfo.length;
		pending = new uint256[](length);
		for (uint256 pid = 0; pid < length; ++pid) {
			pending[pid] = _pendingRSOV(pid, _user);
		}
	}
}
