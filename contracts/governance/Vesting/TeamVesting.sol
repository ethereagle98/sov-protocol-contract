pragma solidity ^0.5.17;
pragma experimental ABIEncoderV2;

import "./Vesting.sol";

/**
 * A regular vesting contract, but the owner of the remaining locked tokens can be changed by the owner (governance)
 **/
contract TeamVesting is Vesting {
	event TokenOwnerChanged(address indexed oldOwner, address indexed newOwner);

	constructor(
		address _SOV,
		address _stakingAddress,
		address _tokenOwner,
		uint256 _cliff,
		uint256 _duration,
		address _feeSharingProxy
	) public Vesting(_SOV, _stakingAddress, _tokenOwner, _cliff, _duration, _feeSharingProxy) {}

	//TODO deprecated
	/**
	 * @notice withdraws the unlocked tokens to the current owner and transfers the ownership of the locked tokens to a new owner
	 * @param newTokenOwner the address of the new owner
	 * */
	function transferTokenOwnership(address newTokenOwner) public onlyOwner {
		require(newTokenOwner != address(0), "owner needs to be a valid address");
		address oldTokenOwner = tokenOwner;
		//withdraw the unlocked tokens to the old token owner address
		_withdrawTokens(oldTokenOwner, false);
		//set the new token owner
		tokenOwner = newTokenOwner;
		//delegate votes to the new owner
		_changeDelegate(newTokenOwner);

		emit TokenOwnerChanged(oldTokenOwner, newTokenOwner);
	}

	/**
	 * @notice delegates the remaining votes to the new token owner
	 * @param newTokenOwner the address of the new token owner
	 * */
	function _changeDelegate(address newTokenOwner) internal {
		for (uint256 i = startDate + cliff; i < endDate; i += FOUR_WEEKS) {
			//only delegate if stake is remaining
			if (staking.getPriorUserStakeByDate(address(this), i, block.number - 1) > 0) staking.delegate(newTokenOwner, i);
		}
	}

	//might also need a function to close the vesting contract completely -> funds get back to the pool
}
