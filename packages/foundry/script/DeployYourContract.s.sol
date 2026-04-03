// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./DeployHelpers.s.sol";
import "../contracts/TreasuryManagerV2.sol";

contract DeployYourContract is ScaffoldETHDeploy {
    // Base mainnet addresses
    address constant OWNER = 0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant TUSD = 0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07;
    address constant STAKING_CONTRACT = 0x2a70a42BC0524aBCA9Bff59a51E7aAdB575DC89A;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;

    // USDC/WETH V3 pool on Base (Uniswap V3, 0.05% fee)
    address constant USDC_WETH_POOL = 0xd0b53D9277642d899DF5C87A3966A349A798F224;
    // ₸USD/WETH V3 pool on Base
    address constant TUSD_POOL = 0xd013725b904e76394A3aB0334Da306C505D778F8;
    // Chainlink ETH/USD price feed on Base
    address constant CHAINLINK_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    function run() external ScaffoldEthDeployerRunner {
        TreasuryManagerV2 tm = new TreasuryManagerV2(
            OWNER,
            WETH,
            USDC,
            TUSD,
            STAKING_CONTRACT,
            UNIVERSAL_ROUTER,
            POOL_MANAGER,
            TUSD_POOL,
            USDC_WETH_POOL,
            CHAINLINK_ETH_USD
        );

        console.logString(string.concat("TreasuryManagerV2 deployed at: ", vm.toString(address(tm))));
    }
}
