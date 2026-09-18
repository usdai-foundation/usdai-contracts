// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    ProxyAdmin, Ownable, ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {StakedUSDai} from "src/StakedUSDai.sol";

/**
 * @title Staked USDai upgrade test
 *
 * @author USD.AI Foundation
 *
 * @dev Forks Arbitrum, upgrades the live Staked USDai proxy to a freshly
 *      compiled implementation, and validates that the observable state is
 *      preserved
 */
contract UpgradeStakedUSDaiTest is Test {
    /* Loan router V2 (lib/usdai-loan-router-contracts/deployments/arbitrum.json) */
    address internal constant LOAN_ROUTER_V2 = 0x1C2ED170de32846316784c4fd58A5e3C7563E12f;

    /* Admin fee recipient */
    address internal constant ADMIN_FEE_RECIPIENT = 0x5F0BC72FB5952b2f3F2E11404398eD507B25841F;

    /* Base yield admin fee rate (10%) */
    uint256 internal constant BASE_YIELD_ADMIN_FEE_RATE = 1000;

    /* Loan router admin fee rate (10%) */
    uint256 internal constant LOAN_ROUTER_ADMIN_FEE_RATE = 1000;

    /**
     * @notice Snapshot of Staked USDai getters
     */
    struct Getters {
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        address asset;
        address share;
        address adminFeeRecipient;
        uint256 totalAssets;
        uint256 nav;
        uint256 totalShares;
        uint256 bridgedSupply;
        uint256 depositSharePrice;
        uint256 redemptionSharePrice;
        uint64 redemptionTimestamp;
        uint256 depositsBalance;
        uint256 redemptionsBalance;
        uint256 loanRouterPendingBalance;
        uint256 loanRouterRepaymentBalance;
        uint256 depositTimelockBalance;
        uint256 accrualRate;
        uint256 claimableBaseYield;
        uint256 redemptionQueueIndex;
        uint256 redemptionQueueHead;
        uint256 redemptionQueueTail;
        uint256 redemptionQueuePending;
        uint256 redemptionQueueBalance;
        uint256 convertToShares;
        uint256 convertToAssets;
    }

    StakedUSDai internal stakedUsdai;
    address internal usdai;
    address internal oAdapterStakedUsdai;
    uint64 internal genesisTimestamp;
    address internal proxyAdmin;
    address internal proxyAdminOwner;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));

        /* Load deployment addresses */
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/deployments/arbitrum.json"));
        stakedUsdai = StakedUSDai(stdJson.readAddress(json, ".StakedUSDai"));
        usdai = stdJson.readAddress(json, ".USDai");
        oAdapterStakedUsdai = stdJson.readAddress(json, ".OAdapterStakedUSDai");
        genesisTimestamp = uint64(stdJson.readUint(json, ".GenesisTimestamp"));

        /* Lookup proxy admin and its owner */
        proxyAdmin = address(uint160(uint256(vm.load(address(stakedUsdai), ERC1967Utils.ADMIN_SLOT))));
        proxyAdminOwner = Ownable(proxyAdmin).owner();

        /* Validate hardcoded constructor arguments against live state */
        assertEq(stakedUsdai.asset(), usdai, "asset");
        assertEq(stakedUsdai.adminFeeRecipient(), ADMIN_FEE_RECIPIENT, "adminFeeRecipient");
    }

    function test__UpgradeStakedUSDai() public {
        address implementationBefore = _implementation();

        address implementation = _upgrade();

        /* Validate implementation slot updated */
        assertEq(_implementation(), implementation);
        assertNotEq(implementation, implementationBefore);

        /* Validate implementation version */
        assertEq(stakedUsdai.IMPLEMENTATION_VERSION(), StakedUSDai(implementation).IMPLEMENTATION_VERSION());
    }

    function test__UpgradeStakedUSDaiGettersUnchanged() public {
        Getters memory before = _getters();

        /* Validate fork has live state */
        assertEq(before.name, "Staked USDai");
        assertGt(before.totalSupply, 0);
        assertGt(before.nav, 0);

        _upgrade();

        Getters memory current = _getters();

        assertEq(current.name, before.name, "name");
        assertEq(current.symbol, before.symbol, "symbol");
        assertEq(current.decimals, before.decimals, "decimals");
        assertEq(current.totalSupply, before.totalSupply, "totalSupply");
        assertEq(current.asset, before.asset, "asset");
        assertEq(current.share, before.share, "share");
        assertEq(current.adminFeeRecipient, before.adminFeeRecipient, "adminFeeRecipient");
        assertEq(current.totalAssets, before.totalAssets, "totalAssets");
        assertEq(current.nav, before.nav, "nav");
        assertEq(current.totalShares, before.totalShares, "totalShares");
        assertEq(current.bridgedSupply, before.bridgedSupply, "bridgedSupply");
        assertEq(current.depositSharePrice, before.depositSharePrice, "depositSharePrice");
        assertEq(current.redemptionSharePrice, before.redemptionSharePrice, "redemptionSharePrice");
        assertEq(current.redemptionTimestamp, before.redemptionTimestamp, "redemptionTimestamp");
        assertEq(current.depositsBalance, before.depositsBalance, "depositsBalance");
        assertEq(current.redemptionsBalance, before.redemptionsBalance, "redemptionsBalance");
        assertEq(current.loanRouterPendingBalance, before.loanRouterPendingBalance, "loanRouterPendingBalance");
        assertEq(current.loanRouterRepaymentBalance, before.loanRouterRepaymentBalance, "loanRouterRepaymentBalance");
        assertEq(current.depositTimelockBalance, before.depositTimelockBalance, "depositTimelockBalance");
        assertEq(current.accrualRate, before.accrualRate, "accrualRate");
        assertEq(current.claimableBaseYield, before.claimableBaseYield, "claimableBaseYield");
        assertEq(current.redemptionQueueIndex, before.redemptionQueueIndex, "redemptionQueueIndex");
        assertEq(current.redemptionQueueHead, before.redemptionQueueHead, "redemptionQueueHead");
        assertEq(current.redemptionQueueTail, before.redemptionQueueTail, "redemptionQueueTail");
        assertEq(current.redemptionQueuePending, before.redemptionQueuePending, "redemptionQueuePending");
        assertEq(current.redemptionQueueBalance, before.redemptionQueueBalance, "redemptionQueueBalance");
        assertEq(current.convertToShares, before.convertToShares, "convertToShares");
        assertEq(current.convertToAssets, before.convertToAssets, "convertToAssets");
    }

    /**
     * @notice Helper to deploy a new implementation and upgrade the Staked USDai proxy
     * @return New implementation address
     */
    function _upgrade() internal returns (address) {
        /* Deploy new Staked USDai implementation */
        StakedUSDai implementation = new StakedUSDai(
            usdai,
            LOAN_ROUTER_V2,
            ADMIN_FEE_RECIPIENT,
            genesisTimestamp,
            BASE_YIELD_ADMIN_FEE_RATE,
            LOAN_ROUTER_ADMIN_FEE_RATE,
            oAdapterStakedUsdai
        );

        /* Upgrade proxy */
        vm.prank(proxyAdminOwner);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(stakedUsdai)), address(implementation), ""
        );

        return address(implementation);
    }

    /**
     * @notice Helper to read the implementation address from the proxy
     * @return Implementation address
     */
    function _implementation() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(stakedUsdai), ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    /**
     * @notice Helper to snapshot Staked USDai getters
     * @return Getters snapshot
     */
    function _getters() internal view returns (Getters memory) {
        (uint256 depositsBalance, uint256 redemptionsBalance) = stakedUsdai.balances();
        (uint256 loanRouterPendingBalance, uint256 loanRouterRepaymentBalance) = stakedUsdai.loanRouterBalances();
        (uint256 index, uint256 head, uint256 tail, uint256 pending, uint256 balance) =
            stakedUsdai.redemptionQueueInfo();

        return Getters({
            name: stakedUsdai.name(),
            symbol: stakedUsdai.symbol(),
            decimals: stakedUsdai.decimals(),
            totalSupply: stakedUsdai.totalSupply(),
            asset: stakedUsdai.asset(),
            share: stakedUsdai.share(),
            adminFeeRecipient: stakedUsdai.adminFeeRecipient(),
            totalAssets: stakedUsdai.totalAssets(),
            nav: stakedUsdai.nav(),
            totalShares: stakedUsdai.totalShares(),
            bridgedSupply: stakedUsdai.bridgedSupply(),
            depositSharePrice: stakedUsdai.depositSharePrice(),
            redemptionSharePrice: stakedUsdai.redemptionSharePrice(),
            redemptionTimestamp: stakedUsdai.redemptionTimestamp(),
            depositsBalance: depositsBalance,
            redemptionsBalance: redemptionsBalance,
            loanRouterPendingBalance: loanRouterPendingBalance,
            loanRouterRepaymentBalance: loanRouterRepaymentBalance,
            depositTimelockBalance: stakedUsdai.depositTimelockBalance(),
            accrualRate: stakedUsdai.accrualRate(),
            claimableBaseYield: stakedUsdai.claimableBaseYield(),
            redemptionQueueIndex: index,
            redemptionQueueHead: head,
            redemptionQueueTail: tail,
            redemptionQueuePending: pending,
            redemptionQueueBalance: balance,
            convertToShares: stakedUsdai.convertToShares(1e18),
            convertToAssets: stakedUsdai.convertToAssets(1e18)
        });
    }
}
