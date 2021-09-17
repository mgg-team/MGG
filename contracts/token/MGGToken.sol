// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IUniswapV2Router02} from "../interface/IUniswapV2Router.sol";
import {IUniswapFactory} from "../interface/IUniswapFactory.sol";

contract MGGToken is AccessControl, ERC20("MUD Guild Game", "MGG") {
    using Address for address;

    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    /// @dev The identifier of the role which allows accounts to mint tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    address public uniswapV2RouterAddress;
    address public uniswapV2PairAddress;
    address public stakingFeeCollector;
    address public liquidityFeeCollector;

    bool whiteListInitialized;
    bool public transferFeeOn;
    mapping(address => bool) public isExcludedFromFee;

    event WhiteListInitialized();
    event StakingFeeCollectorUpdated(address stakingFeeCollector);
    event LiquidityFeeCollectorUpdated(address liquidityFeeCollector);
    event WhiteListUpdated(address targetAddress, bool isWhiteList);
    event TransferFeeOnUpdated(bool transferFeeOn);

    constructor (address _stakingFeeCollector, address _liquidityFeeCollector) public {
        require(_stakingFeeCollector != address(0), "MGGToken: stakingFeeCollector address cannot be 0x0");
        require(_liquidityFeeCollector != address(0), "MGGToken: liquidityFeeCollector address cannot be 0x0");

        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);

        stakingFeeCollector = _stakingFeeCollector;
        liquidityFeeCollector = _liquidityFeeCollector;
        transferFeeOn = true;
    }

    function setStakingFeeCollector(address _stakingFeeCollector) external onlyAdmin {
        require(_stakingFeeCollector != address(0), "MGGToken: stakingFeeCollector address cannot be 0x0");
        stakingFeeCollector = _stakingFeeCollector;
        emit StakingFeeCollectorUpdated(stakingFeeCollector);
    }

    function setLiquidityFeeCollector(address _liquidityFeeCollector) external onlyAdmin {
        require(_liquidityFeeCollector != address(0), "MGGToken: liquidityFeeCollector address cannot be 0x0");
        liquidityFeeCollector = _liquidityFeeCollector;
        emit LiquidityFeeCollectorUpdated(liquidityFeeCollector);
    }

    function setTransferFeeOn(bool _transferFeeOn) external onlyAdmin {
        transferFeeOn = _transferFeeOn;
        emit TransferFeeOnUpdated(transferFeeOn);
    }

    function initWhiteList(address _uniswapV2RouterAddress, address _usdtTokenAddress) external onlyAdmin {
        require(!whiteListInitialized, "MGGToken: whiteList already initialized");
        require(_uniswapV2RouterAddress != address(0), "MGGToken: uniswapV2RouterAddress address cannot be 0x0");
        require(_usdtTokenAddress != address(0), "MGGToken: usdtTokenAddress address cannot be 0x0");

        uniswapV2RouterAddress = _uniswapV2RouterAddress;
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_uniswapV2RouterAddress);
        uniswapV2PairAddress = IUniswapFactory(_uniswapV2Router.factory()).createPair(address(this), _usdtTokenAddress);

        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[uniswapV2RouterAddress] = true;

        whiteListInitialized = true;
        emit WhiteListInitialized();
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "MGGToken: only minter");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "MGGToken: only admin");
        _;
    }

    function alterWhitelist(address _targetAddress, bool _isWhiteList) external onlyAdmin {
      require(_targetAddress != address(0), "MGGToken: whiteList address cannot be 0x0");
      isExcludedFromFee[_targetAddress] = _isWhiteList;
      emit WhiteListUpdated(_targetAddress, _isWhiteList);
    }

    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyMinter {
        _burn(_from, _amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _tokenTransfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _tokenTransfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "MGGToken: transfer amount exceeds allowance"));
        return true;
    }

    function _tokenTransfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "MGGToken: transfer from the zero address");
        require(recipient != address(0), "MGGToken: transfer to the zero address");

        bool excludedFromFee = (sender == uniswapV2PairAddress || isExcludedFromFee[sender] || isExcludedFromFee[recipient]);

        if (!excludedFromFee) {
            (uint256 stakingFee, uint256 liquidityFee) = _calculateFees(amount);

            if (liquidityFee > 0) {
                _transfer(sender, liquidityFeeCollector, liquidityFee);
            }

            if (stakingFee > 0) {
                _transfer(sender, stakingFeeCollector, stakingFee);
            }

            amount = amount.sub(stakingFee).sub(liquidityFee);
        }

        _transfer(sender, recipient, amount);
    }

     function _calculateFees(uint256 amount) internal view returns (uint256, uint256){
        if(transferFeeOn){
          uint256 stakingFee = amount.mul(125).div(1000);
          uint256 liquidityFee = amount.mul(125).div(1000);
          return (stakingFee, liquidityFee);
        } else {
          return (0, 0);
        }

    }
}
