// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ICRVBadDebtRepayment} from "./ICRVBadDebtRepayment.sol";
import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";
import {AggregatorV3Interface} from "@chainlink/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

/// @title CRVBadDebtRepayment
/// @author Llama
/// @notice Contract to purchase USDC/aUSDC with CRV. Max of 2M USDC/aUSDC sold, max of 2.65M CRV in
contract CRVBadDebtRepayment is ICRVBadDebtRepayment {
    using SafeERC20 for IERC20;

    /// CRV cap fulfilled
    error ExcessCRVAmountIn(uint256 amountLeft);
    /// AUSDC cap fulfilled
    error ExcessAUSDCPurchased(uint256 amountLeft);
    /// Oracle price is 0 or lower
    error InvalidOracleAnswer();
    /// Need to request more than 0 tokens out
    error OnlyNonZeroAmount();
    /// Need CRV in the contract to call this function
    error NoCRVForRepayment();

    IERC20 public constant CRV = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant AUSDC = IERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    address public constant BAD_DEBTOR = 0x57E04786E231Af3343562C062E0d058F25daCE9E;

    AggregatorV3Interface public constant CRV_USD_FEED =
        AggregatorV3Interface(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);

    uint256 public constant AUSDC_CAP = 2_000_000e6;
    uint256 public constant CRV_CAP = 2_656_355e18;
    uint256 public totalCRVReceived;
    uint256 public totalAUSDCSold;

    /// @inheritdoc ICRVBadDebtRepayment
    function purchase(uint256 _amountIn, bool _toUnderlying) external returns (uint256 amountOut) {
        if (_amountIn == 0) revert OnlyNonZeroAmount();
        if (_amountIn > availableCRVToBeFilled()) revert ExcessCRVAmountIn(availableCRVToBeFilled());

        amountOut = getAmountOut(_amountIn);
        if (amountOut == 0) revert OnlyNonZeroAmount();
        if (amountOut > availableAUSDCToBeSold()) revert ExcessAUSDCPurchased(availableAUSDCToBeSold());

        totalCRVReceived += _amountIn;
        totalAUSDCSold += amountOut;

        CRV.safeTransferFrom(msg.sender, AaveV2Ethereum.COLLECTOR, _amountIn);
        if (_toUnderlying) {
            AUSDC.safeTransferFrom(AaveV2Ethereum.COLLECTOR, address(this), amountOut);
            // Withdrawing entire aUSDC balance in this contract since we can't directly use 'amountOut' as
            // input due to +1/-1 precision issues caused by rounding on aTokens while it's being transferred.
            amountOut = AaveV2Ethereum.POOL.withdraw(address(USDC), type(uint256).max, msg.sender);
            emit Purchase(address(CRV), address(USDC), _amountIn, amountOut);
        } else {
            AUSDC.safeTransferFrom(AaveV2Ethereum.COLLECTOR, msg.sender, amountOut);
            emit Purchase(address(CRV), address(AUSDC), _amountIn, amountOut);
        }

        return amountOut;
    }

    /// @inheritdoc ICRVBadDebtRepayment
    function availableCRVToBeFilled() public view returns (uint256) {
        return CRV_CAP - totalCRVReceived;
    }

    /// @inheritdoc ICRVBadDebtRepayment
    function availableAUSDCToBeSold() public view override returns (uint256) {
        return AUSDC_CAP - totalAUSDCSold;
    }

    /// @inheritdoc ICRVBadDebtRepayment
    function getAmountOut(uint256 _amountIn) public view override returns (uint256) {
        /** 
            The actual calculation is a collapsed version of this to prevent precision loss:
            => amountOut = (amountCRVWei / 10^crvDecimals) * (chainlinkPrice / chainlinkPrecision) * 10^usdcDecimals
            => amountOut = (amountCRVWei / 10^18) * (chainlinkPrice / 10^8) * 10^6
         */

        uint256 amountOut = (_amountIn * getOraclePrice()) / 10**20;
        // 10 bps arbitrage incentive
        return (amountOut * 10010) / 10000;
    }

    /// @inheritdoc ICRVBadDebtRepayment
    function getOraclePrice() public view override returns (uint256) {
        (, int256 price, , , ) = CRV_USD_FEED.latestRoundData();
        if (price <= 0) revert InvalidOracleAnswer();
        return uint256(price);
    }

    /// @inheritdoc ICRVBadDebtRepayment
    function repay() external returns (uint256) {
        if (CRV.balanceOf(AaveV2Ethereum.COLLECTOR) == 0) revert NoCRVForRepayment();
        CRV.approve(address(AaveV2Ethereum.POOL), totalCRVReceived);
        CRV.safeTransferFrom(AaveV2Ethereum.COLLECTOR, address(this), totalCRVReceived);
        return AaveV2Ethereum.POOL.repay(address(CRV), totalCRVReceived, 2, BAD_DEBTOR);
    }

    /// @inheritdoc ICRVBadDebtRepayment
    function rescueTokens(address[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransfer(AaveV2Ethereum.COLLECTOR, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }
}
