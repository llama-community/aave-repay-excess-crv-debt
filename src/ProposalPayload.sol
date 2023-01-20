// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";
import {AaveMisc} from "@aave-address-book/AaveMisc.sol";
import {CRVBadDebtRepayment} from "./CRVBadDebtRepayment.sol";

/**
 * @title Repay Excess CRV Debt on Ethereum v2
 * @author Llama
 * @notice Provides an execute function for Aave governance to execute
 * Governance Forum Post: https://governance.aave.com/t/arfc-repay-excess-crv-debt-on-ethereum-v2/10955
 * Snapshot: https://snapshot.org/#/aave.eth/proposal/0xa9634f562ba88a5cd23fabe515f36094ccb1d13294a5319bc41ead5dc77a23f9
 */
contract ProposalPayload {
    CRVBadDebtRepayment public immutable crvRepayment;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant AUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    constructor(CRVBadDebtRepayment _crvRepayment) {
        crvRepayment = _crvRepayment;
    }

    /// @notice The AAVE governance executor calls this function to implement the proposal.
    function execute() external {
        // Approve this contract to spend USDC balance of Aave V2 Collector to deposit into aUSDC
        uint256 balance = crvRepayment.USDC().balanceOf(AaveV2Ethereum.COLLECTOR);
        AaveMisc.AAVE_ECOSYSTEM_RESERVE_CONTROLLER.transfer(AaveV2Ethereum.COLLECTOR, USDC, address(this), balance);
        crvRepayment.USDC().approve(address(AaveV2Ethereum.POOL), balance);
        AaveV2Ethereum.POOL.deposit(USDC, balance, AaveV2Ethereum.COLLECTOR, 0);

        // Approve the CRV Repayment contract to withdraw up to 2,000,000 units of AUSDC.
        AaveMisc.AAVE_ECOSYSTEM_RESERVE_CONTROLLER.approve(
            AaveV2Ethereum.COLLECTOR,
            AUSDC,
            address(crvRepayment),
            crvRepayment.AUSDC_CAP()
        );

        // Approve the CRV Repayment contract to spend CRV accumulated to repay bad debt
        AaveMisc.AAVE_ECOSYSTEM_RESERVE_CONTROLLER.approve(
            AaveV2Ethereum.COLLECTOR,
            CRV,
            address(crvRepayment),
            crvRepayment.CRV_CAP()
        );
    }
}
