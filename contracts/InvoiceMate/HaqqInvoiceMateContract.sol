// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./SafeERC20.sol";

library SafeMath {
    function tryAdd(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    function trySub(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    function tryMul(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    function tryDiv(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    function tryMod(
        uint256 a,
        uint256 b
    ) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

interface IERC721NFT {
    function safeMint(
        address to,
        uint256 tokenId,
        string memory tokenURI
    ) external;

    function safeBurn(uint256 tokenId) external;

    function transferOwnership(address newOwner) external;
}

contract HaqqInvoiceMateContract is Initializable, AccessControl {
    using SafeMath for uint256;

    modifier greaterThanZero(
        uint256 _principalAmount,
        uint256 _loanTerm,
        uint256 _interestPercentage
    ) {
        require(
            _principalAmount > 0,
            "principal amount must be greater than zero"
        );
        require(_loanTerm > 0, "loan term days must be greater than zero");
        require(
            _principalAmount > 0,
            "interest percentage must be greater than zero"
        );
        _;
    }

    uint256 public daysInterval;
    uint256 public daysInYear;
    uint256 launchTime;
    uint256 percentDivider;
    uint256 tokenId;
    uint256 currentDay;
    uint256 lenderPercentage;
    uint256 poolPercentage;
    uint256 invoiceMatePercentage;
    uint256 currenInvoiceMateFunds;

    address[] public borrowers;
    address[] public lenders;

    address pool;

    bool launch;

    enum BorrowerStatus {
        FINANCEREQUESTED,TOKENIZED,LENDED,
        REPAID,
        REJECTED,
        CLOSED
    }
    IERC20 public usdc;
    IERC721NFT public erc721;

    struct BorrowerData {
        uint256 totalAmount;
        uint256 borrowCount;
        bool isExist;
    }
    struct LenderData {
        uint256 totalAmount;
        uint256 lendCount;
        bool isExist;
    }
    struct BorrowerLoanDetails {
        uint256 assignedNFT;
        address lender;
        uint256 principalAmount;
        uint256 apy;
        uint256 loanStartTime;
        uint256 loanEndTime;
        uint256 requestDate;
        uint256 duration;
        uint256 lendId;
        string tokenURI;
        bool fundsReceived;
        bool repaid;
    }

    struct LenderDetails {
        uint256 usdcAmount;
        uint256 lendStartTime;
        uint256 repaymentReciveTime;
        uint256 repaymentRecived;
        bool claimed;
    }

    mapping(address => mapping(uint256 => BorrowerLoanDetails))
        public _borrowerLoanDetails;
    mapping(address => mapping(uint256 => BorrowerStatus))
        public _userBorrowStatus;
    mapping(address => mapping(uint256 => LenderDetails)) public _lenderDetails;
    mapping(address => BorrowerData) public _borrowerData;
    mapping(address => LenderData) public _lenderData;
    mapping(uint256 => uint256) totalIncomings;
    mapping(uint256 => uint256) totalOutgoings;

    event LoanRequested(
        address indexed borrower,
        uint256 indexed currentId,
        uint256 indexed loanAmount
    );

    event LoanApproved(
        address indexed lender,
        address indexed borrower,
        uint256 indexed principal
    );
     event LoanRejected(
        address indexed borrower,
        uint256 indexed principal,
        uint256 indexed id
    );

    event loanRepaid(
        address indexed borrower,
        address indexed lender,
        uint256 indexed id
    );

    event stateChanged(
        address indexed borrower,
        uint256 indexed principal,
        BorrowerStatus indexed state
    );

    function initialize(
        address _pool,
        address _usdc,
        address _ERC721,
        address _defaultAdmin
    ) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        pool = _pool;
        usdc = IERC20(_usdc);
        erc721 = IERC721NFT(_ERC721);
        launchTime = block.timestamp;
        launch = true;
        percentDivider = 10000;
        daysInterval = 1 days;
        daysInYear = 365;
        lenderPercentage = 10000;
        poolPercentage = 0;
        invoiceMatePercentage = 0;
    }

    function calculateday() public view returns (uint256) {
        return (block.timestamp - launchTime) / daysInterval;
    }

    function updateDay() public {
        if (currentDay != calculateday()) {
            currentDay = calculateday();
        }
    }

    function requestLoan(
        address _borrower,
        uint256 _principalAmount,
        uint256 _loanTerm,
        string memory _tokenURI,
        uint256 _apy
    )
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        greaterThanZero(_principalAmount, _loanTerm, _apy)
        returns (address _user, uint256 _id)
    {
        BorrowerData storage borrower = _borrowerData[_borrower];
        borrower.borrowCount++;
        BorrowerLoanDetails storage userBorrow = _borrowerLoanDetails[
            _borrower
        ][borrower.borrowCount];
        require(_borrower != address(0), "address cannot be zero");
        require(bytes(_tokenURI).length > 0, "IPFS url must not be empty");
        require(borrower.isExist, "borrower has no existence");
        borrower.totalAmount = borrower.totalAmount.add(_principalAmount);
        userBorrow.principalAmount = _principalAmount;
        userBorrow.apy = _apy * 100;
        userBorrow.requestDate = block.timestamp;
        userBorrow.duration = _loanTerm;
        userBorrow.tokenURI = _tokenURI;
        emit LoanRequested(_borrower, borrower.borrowCount, _principalAmount);
        _id = borrower.borrowCount;
        _user = _borrower;
         setBorrowerStatus(_borrower, _id, BorrowerStatus.FINANCEREQUESTED);
    }
      function rejectLoan(address _user, uint256 _id) public onlyRole(DEFAULT_ADMIN_ROLE) {
        BorrowerData storage user = _borrowerData[_user];
        BorrowerLoanDetails storage userBorrow = _borrowerLoanDetails[_user][
            _id
        ];
        require(user.isExist, "borrower dont exist");
        require(userBorrow.principalAmount > 0, "Borrower Id dont Exists");
        setBorrowerStatus(_user, _id, BorrowerStatus.REJECTED);
        emit LoanRejected(_user, userBorrow.principalAmount, _id);
    }


    function approveloan(
        address _lender,
        address _borrower,
        uint256 _id
    ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        tokenId++;
        BorrowerData storage borrower = _borrowerData[_borrower];
        LenderData storage lender = _lenderData[_lender];
        BorrowerLoanDetails storage userBorrow = _borrowerLoanDetails[
            _borrower
        ][_id];
        BorrowerStatus currentStatus = _userBorrowStatus[_borrower][_id];
        require(
            currentStatus != BorrowerStatus.REJECTED,
            "This loan request is rejected!"
        );
        require(lender.isExist, "lender has no existence");
        require(userBorrow.loanStartTime == 0, "Already financed");
        require(borrower.isExist, "borrower has no existence");
        require(userBorrow.principalAmount > 0, "wrong Id");
        require(
            getUSDCBalance(_lender) >= userBorrow.principalAmount,
            "Lender balance not enough"
        );
        SafeERC20.safeTransferFrom(
            usdc,
            _lender,
            address(this),
            userBorrow.principalAmount
        );
        SafeERC20.safeTransfer(usdc, _borrower, userBorrow.principalAmount);
        userBorrow.assignedNFT = tokenId;
        userBorrow.loanStartTime = block.timestamp;
        userBorrow.loanEndTime =
            block.timestamp +
            (userBorrow.duration * daysInterval);
        mintNFT(_borrower, tokenId, userBorrow.tokenURI);
        setLendingDetails(_lender, userBorrow.principalAmount, _borrower, _id);
        userBorrow.fundsReceived = true;
        setBorrowerStatus(_borrower, _id, BorrowerStatus.TOKENIZED);
        updateDay();
        totalIncomings[currentDay] += userBorrow.principalAmount;
        emit LoanApproved(_lender, _borrower, userBorrow.principalAmount);
        return true;
    }

    function setLendingDetails(
        address _lender,
        uint256 _usdcAmount,
        address _borrower,
        uint256 _id
    ) internal {
        BorrowerLoanDetails storage userBorrow = _borrowerLoanDetails[
            _borrower
        ][_id];
        LenderData storage lender = _lenderData[_lender];
        lender.lendCount++;
        LenderDetails storage lending = _lenderDetails[_lender][
            lender.lendCount
        ];
        lender.totalAmount = lender.totalAmount.add(_usdcAmount);
        lending.usdcAmount = _usdcAmount;
        lending.lendStartTime = block.timestamp;
        userBorrow.lender = _lender;
        userBorrow.lendId = lender.lendCount;
         setBorrowerStatus(_borrower, _id, BorrowerStatus.LENDED);
    }

    function repayLoan(
        address _borrower,
        uint256 _id
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        BorrowerData storage borrower = _borrowerData[_borrower];
        BorrowerLoanDetails storage userBorrow = _borrowerLoanDetails[
            _borrower
        ][_id];
        LenderDetails storage lending = _lenderDetails[userBorrow.lender][
            userBorrow.lendId
        ];
        require(borrower.isExist, "borrower has no existence");
        require(!userBorrow.repaid, "borrower have already paid loan Amount");
        uint256 amount = getBorrowertotalRepayment(_borrower, _id);
        uint256 lenderShare = (amount * lenderPercentage) / percentDivider;
        uint256 poolShare = (amount * poolPercentage) / percentDivider;
        uint256 invoiceMateShare = (amount * invoiceMatePercentage) /
            percentDivider;
        currenInvoiceMateFunds += invoiceMateShare;
        SafeERC20.safeTransferFrom(
            usdc,
            _borrower,
            address(this),
            userBorrow.principalAmount + amount
        );
        SafeERC20.safeTransfer(
            usdc,
            userBorrow.lender,
            userBorrow.principalAmount + lenderShare
        );
        if (poolShare > 0) {
            SafeERC20.safeTransfer(usdc, pool, poolShare);
        }
        burnNFT(userBorrow.assignedNFT);
        userBorrow.repaid = true;
        lending.claimed = true;
        lending.repaymentReciveTime = block.timestamp;
        lending.repaymentRecived = userBorrow.principalAmount + lenderShare;
        setBorrowerStatus(_borrower, _id, BorrowerStatus.REPAID);
        updateDay();
        totalOutgoings[currentDay] += userBorrow.principalAmount + lenderShare;
        emit loanRepaid(_borrower, userBorrow.lender, _id);
    }

    function getBorrowertotalRepayment(
        address _borrower,
        uint256 _id
    ) public view returns (uint256) {
        BorrowerLoanDetails memory userBorrow = _borrowerLoanDetails[_borrower][
            _id
        ];
        uint256 amount = ((userBorrow.principalAmount * userBorrow.apy) /
            percentDivider) / daysInYear;
        uint256 timeMultiplier;
        uint256 durationinDays = (block.timestamp - userBorrow.loanStartTime) /
            daysInterval;
        if (durationinDays <= userBorrow.duration + 1) {
            timeMultiplier = userBorrow.duration;
        } else {
            timeMultiplier = durationinDays;
        }
        amount = timeMultiplier * amount;
        return amount;
    }

    function changeStateOfLoan(
        address _borrower,
        uint256 _id,
        BorrowerStatus _state
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        BorrowerData storage user = _borrowerData[_borrower];
        BorrowerLoanDetails storage userBorrow = _borrowerLoanDetails[
            _borrower
        ][_id];
        require(user.isExist, "borrower has no existence");
        require(userBorrow.principalAmount > 0, "Borrower Id has no existence");
        setBorrowerStatus(_borrower, _id, _state);
        emit stateChanged(_borrower, userBorrow.principalAmount, _state);
    }

    function setBorrowerStatus(
        address _user,
        uint256 _id,
        BorrowerStatus _status
    ) internal {
        _userBorrowStatus[_user][_id] = _status;
    }
    function getBorrowerStatus(address _borrower,uint256 _id)
        public
        view
        returns (string memory _status)
    {
        BorrowerStatus status = _userBorrowStatus[_borrower][_id];
       if (status == BorrowerStatus.FINANCEREQUESTED) {
            _status = "FINANCEREQUESTED";
        } else if (status == BorrowerStatus.TOKENIZED) {
            _status = "TOKENIZED";
        } else if (status == BorrowerStatus.LENDED) {
            _status = "LENDED";
        } else if (status == BorrowerStatus.CLOSED) {
            _status = "CLOSED";
        } else if (status == BorrowerStatus.REPAID) {
            _status = "REPAID";
        } else if (status == BorrowerStatus.REJECTED) {
            _status = "REJECTED";
        }
    }

    function mintNFT(
        address _borrower,
        uint256 _id,
        string memory _tokenURI
    ) internal {
        erc721.safeMint(_borrower, _id, _tokenURI);
    }

    function burnNFT(uint256 _tokenId) internal {
        erc721.safeBurn(_tokenId);
    }

    function getUSDCBalance(address user) public view returns (uint256) {
        return usdc.balanceOf(user);
    }

    function currentState()
        public
        view
        returns (uint256 _incomings, uint256 _outgoinings)
    {
        _incomings = totalIncomings[currentDay];
        _outgoinings = totalOutgoings[currentDay];
    }

    function withdrawFunds(
        uint256 _amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        SafeERC20.safeTransfer(usdc, msg.sender, _amount);
        currenInvoiceMateFunds -= _amount;
    }

    function whitlistLenderAddress(
        address _lender
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_lenderData[_lender].isExist) lenders.push(_lender);
        _lenderData[_lender].isExist = true;
    }

    function whitlistBorrowAddress(
        address _borrower
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_borrowerData[_borrower].isExist) borrowers.push(_borrower);
        _borrowerData[_borrower].isExist = true;
    }

    function getBorrowersLength() public view returns (uint256) {
        return borrowers.length;
    }

    function getLendersLength() public view returns (uint256) {
        return lenders.length;
    }


    function setpercentageMultiplier(
        uint256 _val1,
        uint256 val2,
        uint256 val3 // with 2 extra zeros
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        lenderPercentage = _val1;
        poolPercentage = val2;
        invoiceMatePercentage = val3;
    }

    function setPoolAddress(address _pool) public onlyRole(DEFAULT_ADMIN_ROLE) {
        pool = _pool;
    }

    function transferERC721Ownership(
        address _newOwner
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        erc721.transferOwnership(_newOwner);
    }

    function getBorrowerLoanDetails(
        address _user,
        uint256 _id
    ) public view returns (BorrowerLoanDetails memory) {
        return _borrowerLoanDetails[_user][_id];
    }

    function borrowerExist(address user) public view returns (bool) {
        return _borrowerData[user].isExist;
    }

    function lenderExist(address user) public view returns (bool) {
        return _lenderData[user].isExist;
    }
    function changeUSDC(address _newUsdc) public onlyRole(DEFAULT_ADMIN_ROLE) {
        usdc = IERC20(_newUsdc);
    }
    function changePool(address _newPool) public onlyRole(DEFAULT_ADMIN_ROLE){
        pool = _newPool;
    }
}
