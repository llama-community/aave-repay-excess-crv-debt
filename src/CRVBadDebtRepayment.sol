// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";
import {AggregatorV3Interface} from "@chainlink/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

/// @title CRVBadDebtRepayment
/// @author Llama
/// @notice Contract to purchase USDC/aUSDC with CRV. Max of 2M USDC/aUSDC sold, max of 2.65M CRV in
contract CRVBadDebtRepayment {
    using SafeERC20 for IERC20;

    uint256 public constant AUSDC_CAP = 2_000_000e6;
    uint256 public constant CRV_CAP = 2_656_355e18;
    uint256 public totalCRVReceived;
    uint256 public totalAUSDCSold;

    IERC20 public constant CRV = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant AUSDC = IERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);

    AggregatorV3Interface public constant CRV_USD_FEED =
        AggregatorV3Interface(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);

    address public constant BAD_DEBTOR = 0x57E04786E231Af3343562C062E0d058F25daCE9E;

    event Purchase(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /// CRV cap fulfilled
    error ExcessCRVAmountIn(uint256 amountLeft);
    /// AUSDC cap fulfilled
    error ExcessAUSDCPurchased(uint256 amountLeft);
    /// Not enough CRV in contract to repay bad debt
    error NotEnoughCRV(uint256 amount);
    /// Oracle price is 0 or lower
    error InvalidOracleAnswer();
    /// Need to request more than 0 tokens out
    error OnlyNonZeroAmount();

    /// @notice Purchase USDC for CRV
    /// @param amountIn Amount of CRV input
    /// @param toUnderlying Whether to receive as USDC (true) or aUSDC (false)
    /// @return amountOut Amount of USDC received
    /// @dev Purchaser has to approve CRV transfer before calling this function
    function purchase(uint256 amountIn, bool toUnderlying) external returns (uint256 amountOut) {
        if (amountIn == 0) revert OnlyNonZeroAmount();
        if (amountIn > availableCRVToBeFilled()) revert ExcessCRVAmountIn(availableCRVToBeFilled());

        amountOut = getAmountOut(amountIn);
        if (amountOut == 0) revert OnlyNonZeroAmount();
        if (amountOut > availableAUSDCToBeSold()) revert ExcessAUSDCPurchased(availableAUSDCToBeSold());

        totalCRVReceived += amountIn;
        totalAUSDCSold += amountOut;

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

    /// @notice Returns how close to the 2,000,000 aUSDC amount cap we are
    /// @return availableAUSDCToBeSold the amount of aUSDC left to be sold
    /// @dev Purchaser check this function before calling purchase() to see if there is aUSDC left to be sold
    function availableAUSDCToBeSold() public view returns (uint256) {
        return AUSDC_CAP - totalAUSDCSold;
    }

    function getAmountOut(uint256 amountIn) public view returns (uint256) {
        /** 
            The actual calculation is a collapsed version of this to prevent precision loss:
            => amountOut = (amountCRVWei / 10^balDecimals) * (chainlinkPrice / chainlinkPrecision) * 10^usdcDecimals
            => amountOut = (amountCRVWei / 10^18) * (chainlinkPrice / 10^8) * 10^6
         */

        uint256 amountOut = (amountIn * getOraclePrice()) / 10**20;
        // 10 bps arbitrage incentive
        return (amountOut * 10010) / 10000;
    }

    function getOraclePrice() public view returns (uint256) {
        (, int256 price, , , ) = CRV_USD_FEED.latestRoundData();
        if (price <= 0) revert InvalidOracleAnswer();
        return uint256(price);
    }

    /// @notice Repays CRV debt on behalf of BAD_DEBTOR address
    /// @dev Check balance of contract before repaying to ensure it has enough funds
    function repay() external returns (uint256) {
        if (totalCRVReceived < CRV_CAP) revert NotEnoughCRV(totalCRVReceived);
        CRV.approve(address(AaveV2Ethereum.POOL), totalCRVReceived);
        CRV.safeTransferFrom(AaveV2Ethereum.COLLECTOR, address(this), totalCRVReceived);
        return AaveV2Ethereum.POOL.repay(address(CRV), totalCRVReceived, 2, BAD_DEBTOR);
    }

    /// @notice Transfer any tokens accidentally sent to this contract to Aave V2 Collector
    /// @param tokens List of token addresses
    function rescueTokens(address[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransfer(AaveV2Ethereum.COLLECTOR, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }
}
