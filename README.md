# AAVE Repay Excess CRV Debt on Ethereum v2

This repository contains the payload to deploy a contract that allows the AAVE collector contract to accumulate CRV in order to repay the bad debt generated by an account per this proposal: https://governance.aave.com/t/arfc-repay-excess-crv-debt-on-ethereum-v2/10955

# Specification

This proposal does the following:

1. Approve the CRVBadDebtRepayment contract to spend up to 3,105,000 USDC/aUSDC from the AAVE V2 Collector contract.

Then, the contract itself has the following functions:

1. `function purchase(uint256 amountIn, bool toUnderlying) external returns (uint256 amountOut)` that allows a user to purchase USDC/aUSDC using CRV. The user receives a 10bps bonus for doing so. The first parameter is the amount of CRV they are sending in `uint256 amountIn` and the second parameter `bool toUnderlying` is for the user to choose whether to receive USDC (true) or aUSDC (false).

2. `function availableCRVToBeFilled() public view returns (uint256)` informs the user on how much CRV is left to be sold to this contract. Users should call this view function before calling purchase to know how much there's available to sell.

3. `function availableAUSDCToBeSold() public view returns (uint256)` informs the user how much USDC/aUSDC is left to be sold. In order to cap the maximum CRV price that the contract wants to repay at, it needs to keep track of how much USDC it has spent already. User should call this function prior to calling purchase to see how much USDC is left.

4. `function getAmountOut(uint256 amountIn) public view returns (uint256 amountOut)` informs the user how much USDC/aUSDC they are going to get out from their purchase, with the 10bps bonus included.

5. `function getOraclePrice() public view returns (uint256)` informs the user the current CRV price, per the specified Chainlink Oracle.

6. `function repay() external returns (uint256)` function that sends the CRV balance of the contract to the AAVE V2 pool to repay the bad debt generated by address `0x57E04786E231Af3343562C062E0d058F25daCE9E`. First check if CRV needed has been accumulated in the contract prior to calling this function as it reverts otherwise.

7. `function rescueTokens(address[] calldata tokens) external` This is a rescue function that can be called by anyone to transfer any tokens accidentally sent to the bonding curve contract to Aave V2 Collector. It takes an input list of token contract addresses.

8. `uint256 public totalCRVReceived` The amount of CRV received by the contract.

9. `uint256 public totalAUSDCSold` The amount of USDC/aUSDC used so far.

## Installation

It requires [Foundry](https://github.com/gakonst/foundry) installed to run. You can find instructions here [Foundry installation](https://github.com/gakonst/foundry#installation).

### GitHub template

It's easiest to start a new project by clicking the ["Use this template"](https://github.com/llama-community/aave-governance-forge-template).

Then clone the templated repository locally and `cd` into it and run the following commands:

```sh
$ npm install
$ forge install
$ forge update
$ git submodule update --init --recursive
```

### Manual installation

If you want to create your project manually, run the following commands:

```sh
$ forge init --template https://github.com/llama-community/aave-governance-forge-template <my-repo>
$ cd <my-repo>
$ npm install
$ forge install
$ forge update
$ git submodule update --init --recursive
```

## Setup

Duplicate `.env.example` and rename to `.env`:

- Add a valid mainnet URL for an Ethereum JSON-RPC client for the `RPC_MAINNET_URL` variable.
- Add a valid Private Key for the `PRIVATE_KEY` variable.
- Add a valid Etherscan API Key for the `ETHERSCAN_API_KEY` variable.

### Commands

- `make build` - build the project
- `make test [optional](V={1,2,3,4,5})` - run tests (with different debug levels if provided)
- `make match MATCH=<TEST_FUNCTION_NAME> [optional](V=<{1,2,3,4,5}>)` - run matched tests (with different debug levels if provided)

### Deploy and Verify

- `make deploy-payload` - deploy and verify payload on mainnet
- `make deploy-proposal`- deploy proposal on mainnet

To confirm the deploy was successful, re-run your test suite but use the newly created contract address.
