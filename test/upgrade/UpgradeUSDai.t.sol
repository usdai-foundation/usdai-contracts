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

import {USDai} from "src/USDai.sol";

/**
 * @title USDai upgrade test
 *
 * @author USD.AI Foundation
 *
 * @dev Forks Arbitrum, upgrades the live USDai proxy to a freshly compiled
 *      implementation, and validates that the observable state is preserved
 */
contract UpgradeUSDaiTest is Test {
    /**
     * @notice Snapshot of USDai getters
     */
    struct Getters {
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        address baseToken;
        uint256 bridgedSupply;
        uint256 baseYieldAccrued;
        uint256 stakedUsdaiBalance;
    }

    USDai internal usdai;
    address internal baseYieldEscrow;
    address internal stakedUsdai;
    address internal oAdapterUsdai;
    address internal proxyAdmin;
    address internal proxyAdminOwner;
    address internal user;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));

        /* Load deployment addresses */
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/deployments/arbitrum.json"));
        usdai = USDai(stdJson.readAddress(json, ".USDai"));
        baseYieldEscrow = stdJson.readAddress(json, ".BaseYieldEscrow");
        stakedUsdai = stdJson.readAddress(json, ".StakedUSDai");
        oAdapterUsdai = stdJson.readAddress(json, ".OAdapterUSDai");

        /* Lookup proxy admin and its owner */
        proxyAdmin = address(uint160(uint256(vm.load(address(usdai), ERC1967Utils.ADMIN_SLOT))));
        proxyAdminOwner = Ownable(proxyAdmin).owner();

        user = makeAddr("user");
    }

    function test__UpgradeUSDai() public {
        address implementationBefore = _implementation();

        address implementation = _upgrade();

        /* Validate implementation slot updated */
        assertEq(_implementation(), implementation);
        assertNotEq(implementation, implementationBefore);

        /* Validate implementation version */
        assertEq(usdai.IMPLEMENTATION_VERSION(), USDai(implementation).IMPLEMENTATION_VERSION());
    }

    function test__UpgradeUSDaiGettersUnchanged() public {
        Getters memory before = _getters();

        /* Validate fork has live state */
        assertEq(before.name, "USDai");
        assertGt(before.totalSupply, 0);

        _upgrade();

        Getters memory current = _getters();

        assertEq(current.name, before.name, "name");
        assertEq(current.symbol, before.symbol, "symbol");
        assertEq(current.decimals, before.decimals, "decimals");
        assertEq(current.totalSupply, before.totalSupply, "totalSupply");
        assertEq(current.baseToken, before.baseToken, "baseToken");
        assertEq(current.bridgedSupply, before.bridgedSupply, "bridgedSupply");
        assertEq(current.baseYieldAccrued, before.baseYieldAccrued, "baseYieldAccrued");
        assertEq(current.stakedUsdaiBalance, before.stakedUsdaiBalance, "stakedUsdaiBalance");
    }

    /**
     * @notice Helper to deploy a new implementation and upgrade the USDai proxy
     * @return New implementation address
     */
    function _upgrade() internal returns (address) {
        /* Deploy new USDai implementation */
        USDai implementation = new USDai(usdai.baseToken(), baseYieldEscrow, stakedUsdai, oAdapterUsdai);

        /* Upgrade proxy */
        vm.prank(proxyAdminOwner);
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(address(usdai)), address(implementation), "");

        return address(implementation);
    }

    /**
     * @notice Helper to read the implementation address from the proxy
     * @return Implementation address
     */
    function _implementation() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(usdai), ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    /**
     * @notice Helper to snapshot USDai getters
     * @return Getters snapshot
     */
    function _getters() internal view returns (Getters memory) {
        return Getters({
            name: usdai.name(),
            symbol: usdai.symbol(),
            decimals: usdai.decimals(),
            totalSupply: usdai.totalSupply(),
            baseToken: usdai.baseToken(),
            bridgedSupply: usdai.bridgedSupply(),
            baseYieldAccrued: usdai.baseYieldAccrued(),
            stakedUsdaiBalance: usdai.balanceOf(stakedUsdai)
        });
    }
}
