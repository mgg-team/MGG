// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import {IUniswapV2Router02} from "../interface/IUniswapV2Router.sol";

contract MGGLiquidityHandler  {

using Address for address;
using SafeMath for uint256;
using SafeERC20 for IERC20;

address public mggToken;
address public usdtToken;
address public uniswapV2RouterAddress;
address public uniToken;

address public governance;
address public pendingGovernance;

event PendingGovernanceUpdated(
  address pendingGovernance
);

event GovernanceUpdated(
  address governance
);

event GHOETokenUpdated(
    address mggToken
);

event USDTUpdated(
    address usdtAddress
);

event UniRouterUpdated(
    address uniRouterAddress
);

event UniTokenUpdated(
    address uniTokenAddress
);



constructor(address _governance, address _mggToken, address _usdtToken, address _uniswapV2RouterAddress, address _uniToken) public {
    require(_governance != address(0), "MGGLiquidityHandler: governance address cannot be 0x0");
    require(_mggToken != address(0), "MGGLiquidityHandler: mggToken address cannot be 0x0");
    require(_usdtToken != address(0), "MGGLiquidityHandler: usdtToken address cannot be 0x0");
    require(_uniswapV2RouterAddress != address(0), "MGGLiquidityHandler: uniswapV2RouterAddress address cannot be 0x0");
    require(_uniToken != address(0), "MGGLiquidityHandler: uniToken address cannot be 0x0");

    governance = _governance;
    mggToken = _mggToken;
    usdtToken = _usdtToken;
    uniswapV2RouterAddress = _uniswapV2RouterAddress;
    uniToken = _uniToken;
}

modifier onlyGovernance() {
    require(msg.sender == governance, "MGGLiquidityHandler: only governance");
    _;
}

function setPendingGovernance(address _pendingGovernance) external onlyGovernance {
  require(_pendingGovernance != address(0), "MGGLiquidityHandler: pending governance address cannot be 0x0");
  pendingGovernance = _pendingGovernance;

  emit PendingGovernanceUpdated(_pendingGovernance);
}

function acceptGovernance() external {
  require(msg.sender == pendingGovernance, "MGGLiquidityHandler: only pending governance");

  address _pendingGovernance = pendingGovernance;
  governance = _pendingGovernance;

  emit GovernanceUpdated(_pendingGovernance);
}

function setGHOEToken(address _mggToken) external onlyGovernance {
  require(_mggToken != address(0), "MGGLiquidityHandler: mggToken address cannot be 0x0");

  mggToken = _mggToken;
  emit GHOETokenUpdated(_mggToken);
}

function setUSDTToken(address _usdtToken) external onlyGovernance {
  require(_usdtToken != address(0), "MGGLiquidityHandler: usdtToken address cannot be 0x0");

  usdtToken = _usdtToken;
  emit USDTUpdated(_usdtToken);
}

function setUnirouter(address _uniswapV2RouterAddress) external onlyGovernance {
  require(_uniswapV2RouterAddress != address(0), "MGGLiquidityHandler: uniswapV2RouterAddress address cannot be 0x0");

  uniswapV2RouterAddress = _uniswapV2RouterAddress;
  emit UniRouterUpdated(_uniswapV2RouterAddress);
}

function setUniToken(address _uniToken) external onlyGovernance {
  require(_uniToken != address(0), "MGGLiquidityHandler: uniToken address cannot be 0x0");

  uniToken = _uniToken;
  emit UniTokenUpdated(_uniToken);
}

function addLiquidity(
        uint256 _mggAmount,
        uint256 _usdtAmount,
        uint256 _amountGHOEMin,
        uint256 _amountUSDTMin,
        address _to,
        uint256 _deadline
    ) external returns (uint amountGHOE, uint amountUSDT, uint liquidity) {
        IERC20 mggTokenCached = IERC20(mggToken);
        mggTokenCached.safeTransferFrom(msg.sender, address(this), _mggAmount);

        IERC20 usdtTokenCached = IERC20(usdtToken);
        usdtTokenCached.safeTransferFrom(msg.sender, address(this), _usdtAmount);

        mggTokenCached.safeApprove(uniswapV2RouterAddress, 0);
        mggTokenCached.safeApprove(uniswapV2RouterAddress, _mggAmount);

        usdtTokenCached.safeApprove(uniswapV2RouterAddress, 0);
        usdtTokenCached.safeApprove(uniswapV2RouterAddress, _usdtAmount);

        // add the liquidity
        (amountGHOE, amountUSDT, liquidity) = IUniswapV2Router02(uniswapV2RouterAddress).addLiquidity(
            address(mggToken),
            address(usdtToken),
            _mggAmount,
            _usdtAmount,
            _amountGHOEMin,
            _amountUSDTMin,
            _to,
            _deadline
        );

        if (_mggAmount.sub(amountGHOE) > 0) {
            mggTokenCached.safeTransfer(msg.sender, _mggAmount.sub(amountGHOE));
        }

        if (_usdtAmount.sub(amountUSDT) > 0) {
            usdtTokenCached.safeTransfer(msg.sender, _usdtAmount.sub(amountUSDT));
        }

    }

    function removeLiquidity(
        uint256 _liquidity,
        uint256 _amountGHOEMin,
        uint256 _amountUSDTMin,
        address _to,
        uint256 _deadline
    ) external returns (uint amountGHOE, uint amountUSDT) {

        IERC20(uniToken).safeTransferFrom(msg.sender, address(this), _liquidity);

        IERC20(uniToken).safeApprove(uniswapV2RouterAddress, 0);
        IERC20(uniToken).safeApprove(uniswapV2RouterAddress, _liquidity);

        // remove the liquidity
        return IUniswapV2Router02(uniswapV2RouterAddress).removeLiquidity(
            mggToken,
            usdtToken,
            _liquidity,
            _amountGHOEMin,
            _amountUSDTMin,
            _to,
            _deadline
        );
    }
  }
