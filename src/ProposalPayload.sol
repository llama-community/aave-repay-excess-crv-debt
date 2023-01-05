// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IAaveEcosystemReserveController} from "./external/aave/IAaveEcosystemReserveController.sol";
import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";

/**
 * @title Repay Excess CRV Debt on Ethereum v2
 * @author Llama
 * @notice Provides an execute function for Aave governance to execute
 * Governance Forum Post: https://governance.aave.com/t/arfc-repay-excess-crv-debt-on-ethereum-v2/10955
 * Snapshot: https://snapshot.org/#/aave.eth/proposal/0xa9634f562ba88a5cd23fabe515f36094ccb1d13294a5319bc41ead5dc77a23f9
 */
contract ProposalPayload {
    address public immutable crvRepayment;
    address public constant AUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;

    constructor(address _crvRepayment) {
        crvRepayment = _crvRepayment;
    }

    /// @notice The AAVE governance executor calls this function to implement the proposal.
    function execute() external {
        // Approve the CRV Repayment contract to withdraw up to 2,000,000 units of AUSDC.
        IAaveEcosystemReserveController(AaveV2Ethereum.COLLECTOR_CONTROLLER).approve(
            AaveV2Ethereum.COLLECTOR,
            AUSDC,
            crvRepayment,
            2_000_000e6
        );
    }
}
