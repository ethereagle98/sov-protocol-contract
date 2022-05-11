pragma solidity ^0.5.17;
pragma experimental ABIEncoderV2;

import "../../../openzeppelin/Ownable.sol";
import "../../../interfaces/IERC20.sol";
import "../../Staking/Staking.sol";
import "../../IFeeSharingProxy.sol";
import "../../ApprovalReceiver.sol";
import "./FourYearVestingStorage.sol";
import "../../../proxy/UpgradableProxy.sol";
import "../../../openzeppelin/Address.sol";

/**
 * @title Four Year Vesting Contract.
 *
 * @notice A four year vesting contract.
 *
 * @dev Vesting contract is upgradable,
 * Make sure the vesting owner is multisig otherwise it will be
 * catastrophic.
 * */
contract FourYearVesting is FourYearVestingStorage, UpgradableProxy {
    /**
     * @notice Setup the vesting schedule.
     * @param _logic The address of logic contract.
     * @param _SOV The SOV token address.
     * @param _tokenOwner The owner of the tokens.
     * @param _feeSharingProxy Fee sharing proxy address.
     * @param _extendDurationTill Duration till the unlocked tokens are extended.
     * */
    constructor(
        address _logic,
        address _SOV,
        address _stakingAddress,
        address _tokenOwner,
        address _feeSharingProxy,
        uint256 _extendDurationTill
    ) public {
        require(Address.isContract(_logic), "_logic not a contract");
        require(_SOV != address(0), "SOV address invalid");
        require(Address.isContract(_SOV), "_SOV not a contract");
        require(_stakingAddress != address(0), "staking address invalid");
        require(Address.isContract(_stakingAddress), "_stakingAddress not a contract");
        require(_tokenOwner != address(0), "token owner address invalid");
        require(_feeSharingProxy != address(0), "feeSharingProxy address invalid");
        require(Address.isContract(_feeSharingProxy), "_feeSharingProxy not a contract");
        require((_extendDurationTill % FOUR_WEEKS) == 0, "invalid duration");

        _setImplementation(_logic);
        SOV = IERC20(_SOV);
        staking = Staking(_stakingAddress);
        tokenOwner = _tokenOwner;
        feeSharingProxy = IFeeSharingProxy(_feeSharingProxy);
        maxInterval = 18 * FOUR_WEEKS;
        extendDurationTill = _extendDurationTill;
    }

    /**
     * @notice Set address of the implementation - vesting owner.
     * @dev Overriding setImplementation function of UpgradableProxy. The logic can only be
     * modified when both token owner and veting owner approve. Since
     * setImplementation can only be called by vesting owner, we also need to check
     * if the new logic is already approved by the token owner.
     * @param _implementation Address of the implementation. Must match with what is set by token owner.
     * */
    function setImplementation(address _implementation) public onlyProxyOwner {
        require(Address.isContract(_implementation), "_implementation not a contract");
        require(newImplementation == _implementation, "address mismatch");
        _setImplementation(_implementation);
        newImplementation = address(0);
    }
}
