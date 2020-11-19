pragma solidity ^0.5.17;
pragma experimental ABIEncoderV2;

import "../../openzeppelin/Ownable.sol";
import "../../interfaces/IERC20.sol";

contract StakingStorage is Ownable{
    ///@notice 2 weeks in seconds
    uint constant TWO_WEEKS = 1209600;
    
    ///@notice the maximum possible voting weight before adding +1 (actually 10, but need 9 for computation)
    uint96 public constant MAX_VOTING_WEIGHT = 9;
    
    ///@notice weight is multiplied with this factor (for allowing decimals, like 1.2x)
    ///@dev MAX_VOTING_WEIGHT * WEIGHT_FACTOR needs to be < 792, because there are 100,000,000 SOV with 18 decimals 
    uint96 public constant WEIGHT_FACTOR = 10;
    
    /// @notice the maximum duration to stake tokens for
    uint public constant MAX_DURATION = 1092 days;
    
    ///@notice the maximum duration ^2
    uint96 constant MAX_DURATION_POW_2 = 1092 * 1092;
    
    ///@notice the timestamp of contract creation. base for the staking period calculation
    uint public kickoffTS;
    
    string name = "SOVStaking";
    
    /// @notice the token to be staked
    IERC20 public SOVToken;
    
    /// @notice A record of each accounts delegate
    mapping (address => address) public delegates;
    
    /// @notice if this flag is set to true, all tokens are unlocked immediately
    bool allUnlocked = false;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");
    
    /*************************** Checkpoints *******************************/
    
    /// @notice A checkpoint for marking the stakes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 stake;
    }
    
    /// @notice A record of tokens to be unstaked at a given time in total
    /// for total voting power computation. voting weights get adjusted bi-weekly
    mapping (uint => mapping (uint32 => Checkpoint)) public totalStakingCheckpoints;
    
    ///@notice The number of total staking checkpoints for each date
    mapping (uint => uint32) public numTotalStakingCheckpoints;
    
    /// @notice A record of tokens to be unstaked at a given time which were delegated to a certain address
    /// for delegatee voting power computation. voting weights get adjusted bi-weekly
    mapping(address => mapping (uint => mapping (uint32 => Checkpoint))) public delegateStakingCheckpoints;
    
    ///@notice The number of total staking checkpoints for each date per delegate
    mapping (address => mapping (uint => uint32)) public numDelegateStakingCheckpoints;
    
    /// @notice A record of tokens to be unstaked at a given time which per user address (address -> lockDate -> stake checkpoint)
    mapping (address => mapping (uint => mapping (uint32 => Checkpoint))) public userStakingCheckpoints;
    
    ///@notice The number of total staking checkpoints for each date per user
    mapping (address => mapping (uint => uint32)) public numUserStakingCheckpoints;

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;
    
}