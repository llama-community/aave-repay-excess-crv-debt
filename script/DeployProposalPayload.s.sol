// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {CRVBadDebtRepayment} from "../src/CRVBadDebtRepayment.sol";
import {ProposalPayload} from "../src/ProposalPayload.sol";

contract DeployProposalPayload is Script {
    function run() external {
        vm.startBroadcast();
        CRVBadDebtRepayment crvRepayment = new CRVBadDebtRepayment();
        new ProposalPayload(crvRepayment);
        vm.stopBroadcast();
    }
}
