//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

//=============================================================================
//IMPORTS
//=============================================================================
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../lib/solmate/src/tokens/ERC4626.sol";
import "./interface/ICYDyson.sol";
import "./interface/IPair.sol";
import "./interface/IFarm.sol";
import "./interface/IERC20.sol";

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
    ICYDyson public immutable CYDYSON_ADDRESS;

    uint public vaultPoints;
    uint public vaultTVL;

    /// @dev Maximum loan-to-value ratio
    uint public constant MAX_LTV = 50;

    //======================== DYSON/USDC POOL INTEGRATION ========================

    /// @dev Address to store the DYSON/USDC pool on Sepolia
    address public constant DYSON_USDC_POOL =
        0xd0f3c7d3d02909014303d13223302eFB80A29Ff3;

    /// @dev Address to store the farm on Sepolia
    address public constant FARM = 0x09E1c1C6b273d7fB7F56066D191B7A15205aFcBc;

    /// @dev Address to store the DYSON token on Sepolia
    address public constant DYSON = 0xeDC2B3Bebbb4351a391363578c4248D672Ba7F9B;

    /// @dev Address to store the USDC token on Sepolia
    address public constant USDC = 0xFA0bd2B4d6D629AdF683e4DCA310c562bCD98E4E;

    struct Position {
        uint index;
        uint spAmount;
        bool hasDepositedAsset;
    }

    mapping(address => mapping(address => uint)) public positionsCount;
    mapping(address => mapping(address => mapping(uint => Position)))
        public positions;

    uint public lastUpdateTime;
    uint public spSnapshot; //sp in farm at last update
    uint public spPending; //sp to be added to pool
    uint public updatePeriod = 1 minutes;
    uint public spPool;
    address public owner;
    uint public dysonPool;
    uint public adminFeeRatio;
    uint private constant MAX_ADMIN_FEE_RATIO = 1e18;

    uint constant MAX_FEE_RATIO = 2 ** 64;

    //=============================================================================
    //EVENTS
    //=============================================================================
    /**
    @dev Emitted when a user deposits assets into the vault
    @param pair The address of the pair
    @param user The address of the user
    @param noteId The ID of the note
    @param positionId The ID of the position
    @param spAmount The amount of SP added to the pool
     */
    event Deposited(
        address indexed pair,
        address indexed user,
        uint noteId,
        uint positionId,
        uint spAmount
    );

    event Deposit();

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

    /**
    @dev Emitted when the vault receives DYSON tokens
    @param ownerAmount The amount of DYSON tokens sent to the owner
    @param poolAmount The amount of DYSON tokens added to the pool
    */
    event DYSONReceived(uint ownerAmount, uint poolAmount);

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
    @param _asset Either DYSN or USDC address based on the DYSN/USDC pool in Dyson Finance
    @param _maxVaultCapacity The maximum capacity of the vault, to control price impact and prevent an imbalance in the pool
    @param _name The name of the points that represent the user's share of the vault
    @param _symbol The symbol of the points that represent the user's share of the vault
    @param _cyDysonAddress The address of the synthetic asset that can be borrowed against the vault
     */
    constructor(
        address _owner,
        ERC20 _asset, // DYSN or USDC
        uint256 _maxVaultCapacity,
        string memory _name,
        string memory _symbol,
        ICYDyson _cyDysonAddress, //cyDyson
        address _treasury
    ) ERC4626(_asset, _name, _symbol) {
        CYDYSON_ADDRESS = _cyDysonAddress;
        MAX_VAULT_CAPACITY = _maxVaultCapacity;
        TREASURY_ADDRESS = _treasury;
        owner = _owner;
    }

    //=============================================================================
    //EXTERNAL FUNCTIONS
    //=============================================================================
    /// @dev integration from dyson finance
    function depositToVault(
        address tokenIn, //DYSN
        address tokenOut, //USDC
        uint8 input //USDC is 8 decimals
    ) external nonReentrant returns (uint output) {
        uint spBefore = _update();
        IERC20(tokenIn).transferFrom(msg.sender, address(this), input);

        //find out if tokenIn is DYSN or USDC
        bool tokenIsDyson = tokenIn == DYSON ? true : false;

        uint minOutput;

        //get the min output from the Router contract
        if (tokenIsDyson) {
            (uint reserve0, uint reserve1) = IPair(DYSON_USDC_POOL)
                .getReserves();
            (uint64 _feeRatio0, ) = IPair(DYSON_USDC_POOL).getFeeRatio();
            uint fee = (uint(_feeRatio0) * input) / MAX_FEE_RATIO;
            uint inputLessFee = input - fee;
            minOutput = (inputLessFee * reserve1) / (reserve0 + inputLessFee);
        } else {
            (uint reserve0, uint reserve1) = IPair(DYSON_USDC_POOL)
                .getReserves();
            (, uint64 _feeRatio1) = IPair(DYSON_USDC_POOL).getFeeRatio();
            uint fee = (uint(_feeRatio1) * input) / MAX_FEE_RATIO;
            uint inputLessFee = input - fee;
            minOutput = (inputLessFee * reserve0) / (reserve1 + inputLessFee);
        }

        return
            _deposit(tokenIn, tokenOut, 1, input, minOutput, 1 days, spBefore);
    }

    /**
     * @dev Borrow function that allows a user to borrow a synthetic asset against the underlying vault asset deposit.
     * @param _amount The amount of synthetic assets to borrow.
     * @notice Check that the borrow amount is at a maximum of 50% of the collateral
     * @notice Check that the user has enough collateral to borrow
     * @notice Mint the synthetic asset to the user
     * @notice Borrow amount must be greater than zero
     * @notice Increase the user's debt, decrease the user's credit
     * @notice WIP: MAKE SURE THAT THE BORROW AMOUNT IS LESS THAN OR EQUAL TO THE LTV
     */
    function borrow(uint256 _amount) external nonReentrant {
        if (!(_amount > 0)) {
            revert BorrowLessThanZero(_amount);
        }
        if (!(_amount <= vaultUsers[msg.sender].credit)) {
            revert BorrowExceedsCredit(_amount, vaultUsers[msg.sender].credit);
        }

        vaultUsers[msg.sender].debt += _amount;
        vaultUsers[msg.sender].credit -= _amount;

        ICYDyson(DYSON_USDC_POOL).mint(msg.sender, _amount);

        emit Borrowed(msg.sender, _amount);
    }

    /**
    @dev Mechanism to redistribute yield
    @dev this will be called automatically in the background when the user connects to the vault
    @notice the yield will be redistributed based on some conditions:
    - Yield will be collected by the vault and redistributed back to users based on their points (representing their share of the vault)
    - 50% of the yield will be used to pay down user's debt (if no debt, then it will be used to increase user's credit)
    - 40% of the yield will be used to increase user's credit
    - 10% of the yield will be used to be sent to the treasury
    @dev formula to calculate the yield by the user
        - first, calculate the user's share of the vault (user's points / total points)
        - then, calculate the user's share of the yield (user's share of the vault * total yield)
        - then, calculate the user's share of the paydown (user's share of the yield * 50%)
        - then, calculate the user's share of the credit reward (user's share of the yield * 40%)
        - then, calculate the user's share of the protocol fee (user's share of the yield * 10%)

    @dev if yield in dy
    */
    function redistributeYield(
        uint index, // 1
        address to // address of this contract
    ) public returns (uint token0Amt, uint token1Amt) {
        Position storage position = positions[DYSON_USDC_POOL][msg.sender][
            index
        ];

        if (vaultUsers[msg.sender].points == 0 || !position.hasDepositedAsset) {
            revert NotADepositor(msg.sender);
        }

        if (
            block.timestamp - vaultUsers[msg.sender].lastRedistributed < 86400
        ) {
            revert YieldRedistributedRecently();
        }

        position.hasDepositedAsset = false;
        (token0Amt, token1Amt) = IPair(DYSON_USDC_POOL).withdraw(
            position.index,
            to
        );

        //token0 is Dyson, token1 is USDC
        (address token0, address token1) = DYSON < USDC
            ? (DYSON, USDC)
            : (USDC, DYSON);

        //do a swap if amount for token1 is 0
        if (token1 == USDC && token1Amt == 0) {
            IPair(DYSON_USDC_POOL).swap0in(
                address(this),
                token0Amt,
                (token0Amt * 90) / 100
            );
        }

        uint totalYield = token0Amt == 0 ? token1Amt : token0Amt;

        //get the user's share of the vault
        uint256 userShareOfVault = (vaultUsers[msg.sender].points * BPS) /
            vaultPoints;

        //get the user's share of the yield
        uint256 userShareOfYield = (userShareOfVault * totalYield) / BPS;

        //get the user's share of the paydown
        uint256 userShareOfPaydown = (userShareOfYield * DEBT_PAYDOWN_RATIO) /
            BPS;

        //get the user's share of the credit reward
        uint256 userShareOfCreditReward = (userShareOfYield *
            CREDIT_REWARD_RATIO) / BPS;

        //get the user's share of the protocol fee
        uint256 userShareOfProtocolFee = (userShareOfYield *
            PROTOCOL_REWARD_RATIO) / BPS;

        //decrease the user's debt.
        //if the user's debt is less than the user's share of the paydown, then the user's debt will be set to zero.
        //if there is no debt, then the user's credit will be increased by the user's share of the paydown
        if (vaultUsers[msg.sender].debt < userShareOfPaydown) {
            vaultUsers[msg.sender].debt = 0;
            vaultUsers[msg.sender].credit += userShareOfPaydown;
            IERC20(USDC).transferFrom(
                address(this),
                address(0),
                userShareOfPaydown
            );
        } else {
            vaultUsers[msg.sender].debt -= userShareOfPaydown;
            IERC20(USDC).transferFrom(
                address(this),
                address(0),
                userShareOfPaydown
            );
        }

        //increase the user's credit by the user's share of the credit reward
        vaultUsers[msg.sender].credit += userShareOfCreditReward;
        IERC20(USDC).transferFrom(
            address(this),
            msg.sender,
            userShareOfCreditReward
        );

        //send the user's share of the protocol fee to the treasury
        IERC20(USDC).transferFrom(
            address(this),
            TREASURY_ADDRESS,
            userShareOfProtocolFee
        );

        //emit the YieldRedistributed event
        emit YieldRedistributed(
            msg.sender,
            userShareOfPaydown,
            userShareOfCreditReward,
            userShareOfProtocolFee
        );
    }
    //=============================================================================
    //INTERNAL FUNCTIONS
    //=============================================================================

    function _update() internal returns (uint spInFarm) {
        if (lastUpdateTime + updatePeriod < block.timestamp) {
            try IFarm(FARM).swap(address(this)) {} catch {}
            lastUpdateTime = block.timestamp;
        }
        spInFarm = IFarm(FARM).balanceOf(address(this));
        if (spInFarm < spSnapshot) {
            spPool += spPending;
            spPending = 0;
            uint newBalance = IERC20(DYSON).balanceOf(address(this));
            if (newBalance > dysonPool) {
                uint dysonAdded = newBalance - dysonPool;
                uint adminFee = (dysonAdded * adminFeeRatio) /
                    MAX_ADMIN_FEE_RATIO;
                uint poolIncome = dysonAdded - adminFee;
                dysonPool += poolIncome;
                IERC20(DYSON).transfer(owner, adminFee);
                emit DYSONReceived(adminFee, poolIncome);
            }
        }
    }

    /**
     * @dev Deposits the underlying asset into the Dyson Finance vault. Either DYSN, or USDC.
     * @param input The amount of the asset to deposit
     */
    function _deposit(
        address tokenIn,
        address tokenOut,
        uint index,
        uint input,
        uint minOutput,
        uint time,
        uint spBefore
    ) internal returns (uint output) {
        //checks
        if (!(input > 0)) {
            revert DepositLessThanZero(input);
        }

        if (!(vaultTVL + input <= MAX_VAULT_CAPACITY)) {
            revert DepositLimitReached();
        }

        //effects
        vaultUsers[msg.sender].collateral += input;
        vaultUsers[msg.sender].credit =
            (vaultUsers[msg.sender].collateral * MAX_LTV) /
            100;
        vaultTVL += input;

        //interactions
        (address token0, ) = sortTokens(tokenIn, tokenOut);
        uint noteCount = IPair(DYSON_USDC_POOL).noteCount(address(this));
        if (tokenIn == token0)
            output = IPair(DYSON_USDC_POOL).deposit0(
                address(this),
                input,
                minOutput,
                time
            );
        else
            output = IPair(DYSON_USDC_POOL).deposit1(
                address(this),
                input,
                minOutput,
                time
            );
        uint spAfter = IFarm(FARM).balanceOf(address(this)); //get a hardcoded address for the farm
        uint spAdded = spAfter - spBefore;
        spPending += spAdded;
        spSnapshot = spAfter;
        uint positionId = positionsCount[DYSON_USDC_POOL][msg.sender];
        Position storage position = positions[DYSON_USDC_POOL][msg.sender][
            positionId
        ];
        position.index = noteCount;
        position.spAmount = spAdded;
        position.hasDepositedAsset = true;
        positionsCount[DYSON_USDC_POOL][msg.sender]++;

        uint256 receivedPoints = deposit(input, msg.sender);
        vaultUsers[msg.sender].points += receivedPoints;
        vaultPoints += receivedPoints;
        users.push(msg.sender);

        emit Deposited(
            DYSON_USDC_POOL,
            msg.sender,
            noteCount,
            positionId,
            spAdded
        );
    }

    //=============================================================================
    //PURE FUNCTIONS
    //=============================================================================
    /// @dev returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "identical addresses");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "zero address");
    }

    function totalAssets() public view override returns (uint256) {
        return vaultTVL;
    }
}
