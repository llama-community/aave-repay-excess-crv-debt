// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

// testing libraries
import "@forge-std/Test.sol";

// contract dependencies
import {GovHelpers} from "@aave-helpers/GovHelpers.sol";
import {ProposalPayload} from "../ProposalPayload.sol";
import {CRVBadDebtRepayment} from "../CRVBadDebtRepayment.sol";
import {DeployMainnetProposal} from "../../script/DeployMainnetProposal.s.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";
import {AggregatorV3Interface} from "@chainlink/interfaces/AggregatorV3Interface.sol";

contract ProposalPayloadE2E is Test {
    event Purchase(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    CRVBadDebtRepayment public crvRepayment;
    ProposalPayload public proposalPayload;

    address public constant CRV_WHALE = 0x28C6c06298d514Db089934071355E5743bf21d60;
    address public constant USDC_WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;
    address public constant ETH_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    address public constant VARIABLE_DEBT_CRV = 0x00ad8eBF64F141f1C81e9f8f792d3d1631c6c684;

    uint256 public constant CRV_AMOUNT_IN = 50_000e18;
    uint256 public proposalId;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 16341536);

        // Deploying One Way Bonding Curve
        crvRepayment = new CRVBadDebtRepayment();

        // Deploy Payload
        proposalPayload = new ProposalPayload(crvRepayment);

        // Create Proposal
        vm.prank(GovHelpers.AAVE_WHALE);
        proposalId = DeployMainnetProposal._deployMainnetProposal(
            address(proposalPayload),
            0x344d3181f08b3186228b93bac0005a3a961238164b8b06cbb5f0428a9180b8a7 // TODO: Replace with actual IPFS Hash
        );

        vm.label(address(crvRepayment), "CRVBadDebtRepayment");
        vm.label(address(proposalPayload), "ProposalPayload");
    }

    function testExecuteProposal() public {
        assertEq(crvRepayment.AUSDC().allowance(AaveV2Ethereum.COLLECTOR, address(crvRepayment)), 0);

        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        assertEq(crvRepayment.AUSDC().balanceOf(AaveV2Ethereum.COLLECTOR), 5591098913952);
        assertEq(crvRepayment.USDC().balanceOf(AaveV2Ethereum.COLLECTOR), 0);
        assertEq(
            crvRepayment.AUSDC().allowance(AaveV2Ethereum.COLLECTOR, address(crvRepayment)),
            crvRepayment.AUSDC_CAP()
        );
        assertEq(crvRepayment.CRV().allowance(AaveV2Ethereum.COLLECTOR, address(crvRepayment)), crvRepayment.CRV_CAP());
    }

    // /************************************
    //  *   POST PROPOSAL EXECUTION TESTS  *
    //  ************************************/

    function testCRVAmountLessThanCap() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        assertLe(crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR), crvRepayment.CRV_CAP());
    }

    function testPurchaseZeroAmountIn() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        vm.expectRevert(CRVBadDebtRepayment.OnlyNonZeroAmount.selector);
        crvRepayment.purchase(0, false);
    }

    function testPurchaseZeroAmountOut() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        vm.expectRevert(CRVBadDebtRepayment.OnlyNonZeroAmount.selector);
        crvRepayment.purchase(1e11, false);
    }

    function testPurchaseHitCRVCeiling() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // totalCrvReceived is storage slot 0
        // Setting current totalCRVReceived to 2,660,000 CRV
        vm.store(address(crvRepayment), bytes32(uint256(0)), bytes32(uint256(2_660_000e18)));

        assertEq(crvRepayment.totalCRVReceived(), 2_660_000e18);
        assertLe(crvRepayment.totalCRVReceived(), crvRepayment.CRV_CAP());

        vm.startPrank(CRV_WHALE);
        crvRepayment.CRV().approve(address(crvRepayment), CRV_AMOUNT_IN);
        vm.expectRevert(
            abi.encodeWithSelector(CRVBadDebtRepayment.ExcessCRVAmountIn.selector, 40000000000000000000000)
        );
        crvRepayment.purchase(CRV_AMOUNT_IN, false);
        vm.stopPrank();
    }

    function testPurchaseUsingUSDCCeilingHit() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // totalAUSDCSold is storage slot 1
        // Setting current totalCRVReceived to 3,100,000 aUSDC
        vm.store(address(crvRepayment), bytes32(uint256(1)), bytes32(uint256(3_100_000e6)));

        vm.startPrank(CRV_WHALE);
        crvRepayment.CRV().approve(address(crvRepayment), CRV_AMOUNT_IN);
        vm.expectRevert(abi.encodeWithSelector(CRVBadDebtRepayment.ExcessAUSDCPurchased.selector, 5_000e6));
        crvRepayment.purchase(CRV_AMOUNT_IN, false);
        vm.stopPrank();
    }

    function testPurchaseWithdrawFromAaveFalse() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        vm.startPrank(CRV_WHALE);
        crvRepayment.CRV().approve(address(crvRepayment), CRV_AMOUNT_IN);

        uint256 initialCollectorAusdcBalance = crvRepayment.AUSDC().balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialCollectorUsdcBalance = crvRepayment.USDC().balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialCollectorCrvBalance = crvRepayment.CRV().balanceOf(address(crvRepayment));
        uint256 initialPurchaserAusdcBalance = crvRepayment.AUSDC().balanceOf(CRV_WHALE);
        uint256 initialPurchaserUsdcBalance = crvRepayment.USDC().balanceOf(CRV_WHALE);
        uint256 initialPurchaserCrvBalance = crvRepayment.CRV().balanceOf(CRV_WHALE);

        assertEq(crvRepayment.totalAUSDCSold(), 0);
        assertEq(crvRepayment.totalCRVReceived(), 0);

        vm.expectEmit(true, true, false, true);
        emit Purchase(address(crvRepayment.CRV()), address(crvRepayment.AUSDC()), CRV_AMOUNT_IN, 27347320000);
        uint256 ausdcAmountOut = crvRepayment.purchase(CRV_AMOUNT_IN, false);

        // Compensating for +1/-1 precision issues when rounding, mainly on aTokens
        assertApproxEqAbs(
            crvRepayment.AUSDC().balanceOf(AaveV2Ethereum.COLLECTOR),
            initialCollectorAusdcBalance - ausdcAmountOut,
            1
        );
        assertEq(crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorCrvBalance + CRV_AMOUNT_IN);
        assertEq(crvRepayment.USDC().balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorUsdcBalance);
        // Compensating for +1/-1 precision issues when rounding, mainly on aTokens
        assertApproxEqAbs(crvRepayment.AUSDC().balanceOf(CRV_WHALE), initialPurchaserAusdcBalance + ausdcAmountOut, 1);
        assertEq(crvRepayment.CRV().balanceOf(CRV_WHALE), initialPurchaserCrvBalance - CRV_AMOUNT_IN);
        assertEq(crvRepayment.USDC().balanceOf(CRV_WHALE), initialPurchaserUsdcBalance);

        assertEq(crvRepayment.totalAUSDCSold(), ausdcAmountOut);
        assertEq(crvRepayment.totalCRVReceived(), CRV_AMOUNT_IN);
    }

    function testPurchaseWithdrawFromAaveTrue() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        vm.startPrank(CRV_WHALE);
        crvRepayment.CRV().approve(address(crvRepayment), CRV_AMOUNT_IN);

        uint256 initialCollectorAusdcBalance = crvRepayment.AUSDC().balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialCollectorCrvBalance = crvRepayment.CRV().balanceOf(address(crvRepayment));
        uint256 initialPurchaserUsdcBalance = crvRepayment.USDC().balanceOf(CRV_WHALE);
        uint256 initialPurchaserCrvBalance = crvRepayment.CRV().balanceOf(CRV_WHALE);

        assertEq(crvRepayment.totalAUSDCSold(), 0);
        assertEq(crvRepayment.totalCRVReceived(), 0);

        vm.expectEmit(true, true, false, true);
        emit Purchase(address(crvRepayment.CRV()), address(crvRepayment.USDC()), CRV_AMOUNT_IN, 27347320000);
        uint256 usdcAmountOut = crvRepayment.purchase(CRV_AMOUNT_IN, true);

        // Aave V2 Collector gets some additional aTokens minted to it due to withdrawal happening in the purchase() function
        // see: https://github.com/aave/protocol-v2/blob/baeb455fad42d3160d571bd8d3a795948b72dd85/contracts/protocol/libraries/logic/ReserveLogic.sol#L265-L325
        assertGe(
            crvRepayment.AUSDC().balanceOf(AaveV2Ethereum.COLLECTOR),
            initialCollectorAusdcBalance - usdcAmountOut
        );
        assertEq(crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorCrvBalance + CRV_AMOUNT_IN);
        assertEq(crvRepayment.USDC().balanceOf(CRV_WHALE), initialPurchaserUsdcBalance + usdcAmountOut);
        assertEq(crvRepayment.CRV().balanceOf(CRV_WHALE), initialPurchaserCrvBalance - CRV_AMOUNT_IN);

        // Compensating for +1/-1 precision issues when rounding while transferring aTokens in the purchase() function
        assertApproxEqAbs(crvRepayment.totalAUSDCSold(), usdcAmountOut, 1);
        assertEq(crvRepayment.totalCRVReceived(), CRV_AMOUNT_IN);
    }

    function testGetAmountOut() public {
        // On this block, it's around ~0.55 per USD
        assertEq(crvRepayment.getAmountOut(1e18), 546946);
    }

    function testOraclePriceZeroAmount() public {
        // Mocking returned value of Price = 0
        vm.mockCall(
            address(crvRepayment.CRV_USD_FEED()),
            abi.encodeWithSelector(crvRepayment.CRV_USD_FEED().latestRoundData.selector),
            abi.encode(uint80(10), int256(0), uint256(2), uint256(3), uint80(10))
        );

        vm.expectRevert(CRVBadDebtRepayment.InvalidOracleAnswer.selector);
        crvRepayment.getOraclePrice();

        vm.clearMockedCalls();
    }

    function testOraclePriceTooHigh() public {
        // Mocking returned value of Price = 1.16
        int256 mockedPrice = 116000000;
        vm.mockCall(
            address(crvRepayment.CRV_USD_FEED()),
            abi.encodeWithSelector(crvRepayment.CRV_USD_FEED().latestRoundData.selector),
            abi.encode(uint80(10), int256(mockedPrice), uint256(2), uint256(3), uint80(10))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CRVBadDebtRepayment.CRVPriceTooHigh.selector,
                mockedPrice,
                crvRepayment.MAX_ORACLE_PRICE()
            )
        );
        crvRepayment.getOraclePrice();

        vm.clearMockedCalls();
    }

    function testOraclePriceNegativeAmount() public {
        // Mocking returned value of Price < 0
        vm.mockCall(
            address(crvRepayment.CRV_USD_FEED()),
            abi.encodeWithSelector(crvRepayment.CRV_USD_FEED().latestRoundData.selector),
            abi.encode(uint80(10), int256(-1), uint256(2), uint256(3), uint80(10))
        );

        vm.expectRevert(CRVBadDebtRepayment.InvalidOracleAnswer.selector);
        crvRepayment.getOraclePrice();

        vm.clearMockedCalls();
    }

    function testGetOraclePrice() public {
        assertEq(crvRepayment.CRV_USD_FEED().decimals(), 8);
        (, int256 price, , , ) = crvRepayment.CRV_USD_FEED().latestRoundData();
        assertEq(uint256(price), 54640000);
        assertEq(crvRepayment.getOraclePrice(), 54640000);
    }

    function testGetOraclePriceAtMultipleIntervals() public {
        // Testing for around 50000 blocks
        // CRV/USD Chainlink price feed updates every 24 hours ~= 6500 blocks
        for (uint256 i = 0; i < 5000; i++) {
            vm.roll(block.number - 10);
            (, int256 price, , , ) = crvRepayment.CRV_USD_FEED().latestRoundData();
            assertEq(crvRepayment.getOraclePrice(), uint256(price));
        }
    }

    function testSendEthtoCRVBadDebtRepayment() public {
        // Testing that you can't send ETH to the contract directly since there's no fallback() or receive() function
        vm.startPrank(ETH_WHALE);
        (bool success, ) = address(crvRepayment).call{value: 1 ether}("");
        assertTrue(!success);
    }

    function testRepayNoCRV() public {
        GovHelpers.passVoteAndExecute(vm, proposalId);

        vm.expectRevert(CRVBadDebtRepayment.NoCRVForRepayment.selector);

        crvRepayment.repay();
    }

    function testRepayPortion() public {
        uint256 expectedVariableDebtTokens = 2_670_411_225358009139073680;
        uint256 variableDebtBalanceTokensBefore = IERC20(VARIABLE_DEBT_CRV).balanceOf(crvRepayment.BAD_DEBTOR());
        assertEq(variableDebtBalanceTokensBefore, expectedVariableDebtTokens);

        GovHelpers.passVoteAndExecute(vm, proposalId);

        vm.startPrank(CRV_WHALE);
        crvRepayment.CRV().approve(address(crvRepayment), 100_000e18);

        crvRepayment.purchase(100_000e18, false);
        vm.stopPrank();

        uint256 amountPaid = crvRepayment.repay();
        uint256 variableDebtTokensAfter = IERC20(VARIABLE_DEBT_CRV).balanceOf(crvRepayment.BAD_DEBTOR());

        assertEq(amountPaid, 100_000e18);
        assertTrue(variableDebtBalanceTokensBefore > variableDebtTokensAfter);
        assertEq(variableDebtTokensAfter, 2570888024685060400087965);
    }

    function testRepaySuccessful() public {
        uint256 ACTUAL_DEBT = 2_670_888_024685060400087965;
        uint256 expectedVariableDebtTokens = 2_670_411_225358009139073680;
        uint256 variableDebtBalanceTokensBefore = IERC20(VARIABLE_DEBT_CRV).balanceOf(crvRepayment.BAD_DEBTOR());
        assertEq(variableDebtBalanceTokensBefore, expectedVariableDebtTokens);

        GovHelpers.passVoteAndExecute(vm, proposalId);

        vm.startPrank(CRV_WHALE);
        crvRepayment.CRV().approve(address(crvRepayment), crvRepayment.CRV_CAP());

        crvRepayment.purchase(crvRepayment.CRV_CAP(), false);
        vm.stopPrank();

        uint256 aaveCollectorCRVBalanceBeforeRepayment = crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR);

        uint256 amountPaid = crvRepayment.repay();

        assertEq(crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR), 0);
        assertEq(amountPaid, ACTUAL_DEBT);
        assertEq(IERC20(VARIABLE_DEBT_CRV).balanceOf(crvRepayment.BAD_DEBTOR()), 0);

        // There's like ~30k CRV left in the swap contract after repayment.
        uint256 crvRepaymentContractCRVBalance = crvRepayment.CRV().balanceOf(address(crvRepayment));
        console.log(crvRepaymentContractCRVBalance);
        assertEq(crvRepaymentContractCRVBalance, aaveCollectorCRVBalanceBeforeRepayment - amountPaid);

        // We can recover it though
        address[] memory tokens = new address[](1);
        tokens[0] = address(crvRepayment.CRV());
        crvRepayment.rescueTokens(tokens);

        assertEq(crvRepayment.CRV().balanceOf(address(crvRepayment)), 0);
        assertEq(crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR), crvRepaymentContractCRVBalance);
    }

    function testRescueTokens() public {
        assertEq(crvRepayment.CRV().balanceOf(address(crvRepayment)), 0);
        assertEq(crvRepayment.USDC().balanceOf(address(crvRepayment)), 0);

        uint256 crvAmount = 10_000e18;
        uint256 usdcAmount = 10_000e6;

        vm.startPrank(CRV_WHALE);
        crvRepayment.CRV().transfer(address(crvRepayment), crvAmount);
        vm.stopPrank();

        vm.startPrank(USDC_WHALE);
        crvRepayment.USDC().transfer(address(crvRepayment), usdcAmount);
        vm.stopPrank();

        assertEq(crvRepayment.CRV().balanceOf(address(crvRepayment)), crvAmount);
        assertEq(crvRepayment.USDC().balanceOf(address(crvRepayment)), usdcAmount);

        uint256 initialCollectorCrvBalance = crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialCollectorUsdcBalance = crvRepayment.USDC().balanceOf(AaveV2Ethereum.COLLECTOR);

        address[] memory tokens = new address[](2);
        tokens[0] = address(crvRepayment.CRV());
        tokens[1] = address(crvRepayment.USDC());
        crvRepayment.rescueTokens(tokens);

        assertEq(crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorCrvBalance + crvAmount);
        assertEq(crvRepayment.USDC().balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorUsdcBalance + usdcAmount);
        assertEq(crvRepayment.CRV().balanceOf(address(crvRepayment)), 0);
        assertEq(crvRepayment.USDC().balanceOf(address(crvRepayment)), 0);
    }

    /*****************************************
     *   POST PROPOSAL EXECUTION FUZZ TESTS  *
     *****************************************/

    function testPurchaseWithdrawFromAaveFalseFuzz(uint256 amount) public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // Assuming upper bound of purchase of 2,650,000 CRV and lower bound of 2 CRV (price is less than 1)
        vm.assume(amount >= 2e18 && amount <= crvRepayment.CRV_CAP());

        vm.startPrank(CRV_WHALE);
        crvRepayment.CRV().approve(address(crvRepayment), amount);

        uint256 initialCollectorAusdcBalance = crvRepayment.AUSDC().balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialCollectorCrvBalance = crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialPurchaserAusdcBalance = crvRepayment.AUSDC().balanceOf(CRV_WHALE);
        uint256 initialPurchaserCrvBalance = crvRepayment.CRV().balanceOf(CRV_WHALE);

        assertEq(crvRepayment.totalAUSDCSold(), 0);
        assertEq(crvRepayment.totalCRVReceived(), 0);

        uint256 ausdcAmountOut = crvRepayment.purchase(amount, false);

        // Compensating for +1/-1 precision issues when rounding, mainly on aTokens
        assertApproxEqAbs(
            crvRepayment.AUSDC().balanceOf(AaveV2Ethereum.COLLECTOR),
            initialCollectorAusdcBalance - ausdcAmountOut,
            1
        );
        assertEq(crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorCrvBalance + amount);
        // Compensating for +1/-1 precision issues when rounding, mainly on aTokens
        assertApproxEqAbs(crvRepayment.AUSDC().balanceOf(CRV_WHALE), initialPurchaserAusdcBalance + ausdcAmountOut, 1);
        assertEq(crvRepayment.CRV().balanceOf(CRV_WHALE), initialPurchaserCrvBalance - amount);

        assertEq(crvRepayment.totalAUSDCSold(), ausdcAmountOut);
        assertEq(crvRepayment.totalCRVReceived(), amount);
    }

    function testPurchaseWithdrawFromAaveTrueFuzz(uint256 amount) public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // Assuming upper bound of purchase of 2,650,000 CRV and lower bound of 2 CRV (price is less than 1)
        vm.assume(amount >= 2e18 && amount <= crvRepayment.CRV_CAP());

        vm.startPrank(CRV_WHALE);
        crvRepayment.CRV().approve(address(crvRepayment), amount);

        uint256 initialCollectorAusdcBalance = crvRepayment.AUSDC().balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialCollectorCrvBalance = crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialPurchaserUsdcBalance = crvRepayment.USDC().balanceOf(CRV_WHALE);
        uint256 initialPurchaserCrvBalance = crvRepayment.CRV().balanceOf(CRV_WHALE);

        assertEq(crvRepayment.totalAUSDCSold(), 0);
        assertEq(crvRepayment.totalCRVReceived(), 0);

        uint256 usdcAmountOut = crvRepayment.purchase(amount, true);

        // Aave V2 Collector gets some additional aTokens minted to it due to withdrawal happening in the purchase() function
        // see: https://github.com/aave/protocol-v2/blob/baeb455fad42d3160d571bd8d3a795948b72dd85/contracts/protocol/libraries/logic/ReserveLogic.sol#L265-L325
        assertApproxEqAbs(
            crvRepayment.AUSDC().balanceOf(AaveV2Ethereum.COLLECTOR),
            initialCollectorAusdcBalance - usdcAmountOut,
            1
        );
        assertEq(crvRepayment.CRV().balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorCrvBalance + amount);
        assertEq(crvRepayment.USDC().balanceOf(CRV_WHALE), initialPurchaserUsdcBalance + usdcAmountOut);
        assertEq(crvRepayment.CRV().balanceOf(CRV_WHALE), initialPurchaserCrvBalance - amount);

        // Compensating for +1/-1 precision issues when rounding while transferring aTokens in the purchase() function
        assertApproxEqAbs(crvRepayment.totalAUSDCSold(), usdcAmountOut, 1);
        assertEq(crvRepayment.totalCRVReceived(), amount);
    }

    function testInvalidPriceFromOracleFuzz(int256 price) public {
        vm.assume(price <= int256(0));

        // Mocking returned value of price <=0
        vm.mockCall(
            address(crvRepayment.CRV_USD_FEED()),
            abi.encodeWithSelector(crvRepayment.CRV_USD_FEED().latestRoundData.selector),
            abi.encode(uint80(10), price, uint256(2), uint256(3), uint80(10))
        );

        vm.expectRevert(CRVBadDebtRepayment.InvalidOracleAnswer.selector);
        crvRepayment.getOraclePrice();

        vm.clearMockedCalls();
    }
}
