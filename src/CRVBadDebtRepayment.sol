// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";
import {AggregatorV3Interface} from "./external/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract CRVBadDebtRepayment {
    using SafeERC20 for IERC20;

    uint256 public constant USD_CAP = 2_000_000e6;
    uint256 public constant CRV_CAP = 2_656_500e18;
    uint256 public totalCRVReceived;
    uint256 public totalUSDCSold;

    IERC20 public constant CRV = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant AUSDC = IERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);

    AggregatorV3Interface public constant CRV_USD_FEED =
        AggregatorV3Interface(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);

    event Purchase(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /// CRV cap fulfilled
    error ExcessCRVAmountIn();
    /// USDC cap fulfilled
    error ExcessUSDCPurchased();
    /// Not enough CRV in contract to repay bad debt
    error NotEnoughCRV();
    /// Oracle price is 0 or lower
    error InvalidOracleAnswer();
    /// Need to request more than 0 tokens out
    error OnlyNonZeroAmount();

    /// @notice Purchase USDC for CRV
    /// @param amountIn Amount of BAL input
    /// @param toUnderlying Whether to receive as USDC (true) or aUSDC (false)
    /// @return amountOut Amount of USDC received
    /// @dev Purchaser has to approve BAL transfer before calling this function
    function purchase(uint256 amountIn, bool toUnderlying) external returns (uint256 amountOut) {
        if (amountIn == 0) revert OnlyNonZeroAmount();
        if (amountIn > availableCRVToBeFilled()) revert ExcessCRVAmountIn();

        amountOut = getAmountOut(amountIn);
        if (amountOut == 0) revert OnlyNonZeroAmount();
        if (amountIn > availableUSDCToBeSold()) revert ExcessUSDCPurchased();

        totalCRVReceived += amountIn;
        totalUSDCSold += amountOut;

        CRV.safeTransferFrom(msg.sender, AaveV2Ethereum.COLLECTOR, amountIn);
        if (toUnderlying) {
            AUSDC.safeTransferFrom(AaveV2Ethereum.COLLECTOR, address(this), amountOut);
            // Withdrawing entire aUSDC balance in this contract since we can't directly use 'amountOut' as
            // input due to +1/-1 precision issues caused by rounding on aTokens while it's being transferred.
            amountOut = AaveV2Ethereum.POOL.withdraw(address(USDC), type(uint256).max, msg.sender);
            emit Purchase(address(CRV), address(USDC), amountIn, amountOut);
        } else {
            AUSDC.safeTransferFrom(AaveV2Ethereum.COLLECTOR, msg.sender, amountOut);
            emit Purchase(address(CRV), address(AUSDC), amountIn, amountOut);
        }

        return amountOut;
    }

    /// @notice Returns how close to the 2,656,500 CRV amount cap we are
    /// @return availableCRVToBeFilled the amount of BAL left to be filled
    /// @dev Purchaser check this function before calling purchase() to see if there is CRV left to be filled
    function availableCRVToBeFilled() public view returns (uint256) {
        return CRV_CAP - totalCRVReceived;
    }

    /// @notice Returns how close to the 2,000,000 USDC amount cap we are
    /// @return availableUSDCToBeSold the amount of USDC left to be sold
    /// @dev Purchaser check this function before calling purchase() to see if there is USDC left to be sold
    function availableUSDCToBeSold() public view returns (uint256) {
        return USD_CAP - totalUSDCSold;
    }

    function getAmountOut(uint256 amountIn) public view returns (uint256 amountOut) {
        /** 
            The actual calculation is a collapsed version of this to prevent precision loss:
            => amountOut = (amountCRVWei / 10^balDecimals) * (chainlinkPrice / chainlinkPrecision) * 10^usdcDecimals
            => amountOut = (amountCRVWei / 10^18) * (chainlinkPrice / 10^8) * 10^6
         */
        amountOut = (amountIn * getOraclePrice()) / 10**20;
        // 10 bps arbitrage incentive
        return (amountOut * 10010) / 10000;
    }

    function getOraclePrice() public view returns (uint256) {
        (, int256 price, , , ) = CRV_USD_FEED.latestRoundData();
        if (price <= 0) revert InvalidOracleAnswer();
        return uint256(price);
    }

    function repay() external {
        if (IERC20(CRV).balanceOf(address(this)) < totalCRVReceived) revert NotEnoughCRV();
        // pool.repay(CRV, CRV_CAP, variableInterest, 0x57e04786e231af3343562c062e0d058f25dace9e);
    }

    /// @notice Transfer any tokens accidentally sent to this contract to Aave V2 Collector
    /// @param tokens List of token addresses
    function rescueTokens(address[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransfer(AaveV2Ethereum.COLLECTOR, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }
}
