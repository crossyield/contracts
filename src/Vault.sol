//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

//=============================================================================
//IMPORTS
//=============================================================================
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../lib/solmate/src/tokens/ERC4626.sol";
// import "./interfaces/ISyntheticToken.sol";

/**
@title Vault
@notice This contract is used to store the yield strategies of the protocol
*/
contract Vault is ERC4626, ReentrancyGuard {
    //=============================================================================
    //STATE VARIABLES
    //=============================================================================
    struct VaultUser {
        uint points;
        uint debt;
        uint credit;
        uint collateral;
        uint lastRedistributed;
    }
    mapping(address => VaultUser) public vaultUsers;
    address[] public users;

    /// @dev 50/40/10 ratio for debt paydown, credit reward, and protocol reward
    uint public constant DEBT_PAYDOWN_RATIO = 5000;
    uint public constant CREDIT_REWARD_RATIO = 4000;
    uint public constant PROTOCOL_REWARD_RATIO = 1000;

    /// @dev Basis points for percentages
    uint public constant BPS = 10_000;

    /// @dev Maximum tokens that can be heled by the vault at a time
    uint public immutable MAX_VAULT_CAPACITY;

    /// @dev Addresses to track synthetic asset and treasury
    address public immutable TREASURY_ADDRESS;
    ISyntheticToken public immutable SYNTHETIC_ASSET_ADDRESS;

    uint public vaultPoints;
    uint public vaultTVL;

    //=============================================================================
    //EVENTS
    //=============================================================================
    /**
    @dev Emitted when a user deposits assets into the vault
    @param user The address of the user
    @param assets The amount of assets deposited
    @param points The amount of points minted
     */
    event Deposited(address indexed user, uint assets, uint points);

    /**
    @dev Emitted when a user borrows synthetic assets
    @param user The address of the user
    @param amount The amount of synthetic assets borrowed
    */
    event Borrowed(address indexed user, uint256 amount);

    /**
    @dev Emitted when the yield is redistributed
    @param user The address of the user
    @param paydown The amount of the user's share of the paydown
    @param creditReward The amount of the user's share of the credit reward
    @param protocolFee The amount of the user's share of the protocol fee
    */
    event YieldRedistributed(
        address indexed user,
        uint paydown,
        uint creditReward,
        uint protocolFee
    );

    //=============================================================================
    //ERRORS
    //=============================================================================
    /**
    @dev Error when the deposit amount is less than zero
    @param _assets The amount of assets deposited
    */
    error DepositLessThanZero(uint _assets);

    /**
    @dev Error when the deposit limit is reached 
    */
    error DepositLimitReached();

    /**
    @dev Error when the withdraw receiver address is zero
    */
    error ZeroAddress();

    /**
    @dev Error when the withdraw caller has not made a deposit
    @param _caller The address of the caller
    */
    error NotADepositor(address _caller);

    /**
    @dev Error when the borrow amount is less than zero
    @param _amount The amount of synthetic assets borrowed
    */
    error BorrowLessThanZero(uint _amount);

    /**
    @dev Error when the borrow amount is more than the user's credit
    @param _amount The amount of synthetic assets borrowed
    @param _credit The amount of synthetic assets the user can borrow
    */
    error BorrowExceedsCredit(uint _amount, uint _credit);

    /**
     * @dev Error when the user's yield has been redistributed in the last 24 hours
     */
    error YieldRedistributedRecently();

    /**
    @dev Error when the user has insufficient synthetic assets to repay
    @param _amount The amount of synthetic assets repaid
    @param _balance The amount of synthetic assets the user has
    */
    error InsufficientSyntheticAssets(uint _amount, uint _balance);

    //=============================================================================
    //CONSTRUCTOR
    //=============================================================================
    /**
    @dev Initializes the vault with the underlying asset, name, symbol, and synthetic assets.
    @param _asset Either WETH or USDC address based on the WETH/USDC pool in Dyson Finance
    @param _maxVaultCapacity The maximum capacity of the vault, to control price impact and prevent an imbalance in the pool
    @param _name The name of the points that represent the user's share of the vault
    @param _symbol The symbol of the points that represent the user's share of the vault
    @param _syntheticAsset The address of the synthetic asset that can be borrowed against the vault
     */
    constructor(
        ERC20 _asset,
        uint256 _maxVaultCapacity,
        string memory _name,
        string memory _symbol,
        ISyntheticToken _syntheticAsset,
        address _treasury
    ) ERC4626(_asset, _name, _symbol) {
        SYNTHETIC_ASSET_ADDRESS = _syntheticAsset;
        MAX_VAULT_CAPACITY = _maxVaultCapacity;
        TREASURY_ADDRESS = _treasury;
    }
}
