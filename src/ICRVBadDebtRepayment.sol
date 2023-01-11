// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

interface ICRVBadDebtRepayment {
    event Purchase(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /// @notice Purchase USDC for CRV
    /// @param _amountIn Amount of CRV input
    /// @param _toUnderlying Whether to receive as USDC (true) or aUSDC (false)
    /// @return amountOut Amount of USDC received
    /// @dev Purchaser has to approve CRV transfer before calling this function
    function purchase(uint256 _amountIn, bool _toUnderlying) external returns (uint256 amountOut);

    /// @notice Returns how close to the 2,656,500 CRV amount cap we are
    /// @return availableCRVToBeFilled the amount of CRV left to be filled
    /// @dev Purchaser check this function before calling purchase() to see if there is CRV left to be filled
    function availableCRVToBeFilled() external view returns (uint256);

    /// @notice Returns how close to the 2,000,000 aUSDC amount cap we are
    /// @return availableAUSDCToBeSold the amount of aUSDC left to be sold
    /// @dev Purchaser check this function before calling purchase() to see if there is aUSDC left to be sold
    function availableAUSDCToBeSold() external view returns (uint256);

    /// @notice Returns amount of USDC to be sent to purchaser
    /// @param _amountIn the amount of CRV sent
    /// return amountOut the amount of USDC plus premium incentive returned
    /// @dev User check this function before calling purchase() to see the amount of USDC to be sent
    function getAmountOut(uint256 _amountIn) external view returns (uint256);

    /// @notice The peg price of the referenced oracle as USD per CRV
    function getOraclePrice() external view returns (uint256);

    /// @notice Repays CRV debt on behalf of BAD_DEBTOR address
    function repay() external returns (uint256);

    /// @notice Transfer any tokens accidentally sent to this contract to Aave V2 Collector
    /// @param tokens List of token addresses
    function rescueTokens(address[] calldata tokens) external;
}
