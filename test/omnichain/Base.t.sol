// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

// Forge imports

// Test imports

// Implementation imports
import {OAdapter} from "src/omnichain/OAdapter.sol";
import {OToken} from "src/omnichain/OToken.sol";

// OApp imports
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import {RateLimiter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

// OZ imports
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

// DevTools imports
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

// Implementation imports
import {OUSDaiUtility} from "src/omnichain/OUSDaiUtility.sol";
import {USDai} from "src/USDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";

// Mock imports
import {MockLoanRouter} from "../mocks/MockLoanRouter.sol";

// Interface imports
import {IUSDai} from "src/interfaces/IUSDai.sol";
import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";

/**
 * @title Omnichain Base test setup
 * @author USD.AI Foundation
 * @author Modified from https://github.com/PaulRBerg/prb-proxy/blob/main/test/Base.t.sol
 *
 * @notice Deploys the real USDai and StakedUSDai contracts against the LayerZero test harness.
 *         The only stub is the loan router, which reports no positions so the vault valuation
 *         reduces to its USDai deposit balance.
 */
abstract contract OmnichainBaseTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 internal usdtHomeEid = 1;
    uint32 internal usdtAwayEid = 2;
    uint32 internal usdaiHomeEid = 3;
    uint32 internal usdaiAwayEid = 4;
    uint32 internal stakedUsdaiHomeEid = 5;
    uint32 internal stakedUsdaiAwayEid = 6;

    OToken internal usdtHomeToken;
    OToken internal usdtAwayToken;
    OToken internal usdaiAwayToken;
    OToken internal stakedUsdaiAwayToken;

    OAdapter internal usdtHomeOAdapter;
    OAdapter internal usdtAwayOAdapter;

    OAdapter internal usdaiHomeOAdapter;
    OAdapter internal usdaiAwayOAdapter;

    OAdapter internal stakedUsdaiHomeOAdapter;
    OAdapter internal stakedUsdaiAwayOAdapter;

    OUSDaiUtility internal oUsdaiUtility;

    MockLoanRouter internal mockLoanRouter;

    uint256 internal initialBalance = 20_000_000 ether;

    IUSDai internal usdai;
    IStakedUSDai internal stakedUsdai;

    address internal user = address(0x1);
    address internal blacklistedUser = address(0x2);

    /**
     * @notice Deploy an OToken behind a proxy with no adapter wired yet
     * @param name Token name and symbol
     * @return Token proxy
     */
    function _deployOToken(
        string memory name
    ) internal returns (OToken) {
        OToken impl = new OToken(address(0));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(this),
            abi.encodeWithSignature("initialize(string,string,address)", name, name, address(this))
        );
        return OToken(address(proxy));
    }

    /**
     * @notice Point an OToken proxy at a fresh implementation bound to its adapter
     * @param token Token proxy
     * @param oAdapter Adapter to bind
     */
    function _bindOTokenAdapter(OToken token, address oAdapter) internal {
        OToken impl = new OToken(oAdapter);
        address proxyAdmin = address(uint160(uint256(vm.load(address(token), ERC1967Utils.ADMIN_SLOT))));
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(address(token)), address(impl), "");
    }

    /**
     * @notice Build a single destination rate limit config
     * @param dstEid Destination endpoint ID
     * @return Rate limit config array
     */
    function _rateLimit(
        uint32 dstEid
    ) internal view returns (RateLimiter.RateLimitConfig[] memory) {
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({dstEid: dstEid, limit: initialBalance, window: 1 days});
        return configs;
    }

    function setUp() public virtual override {
        // Call the base setup function from the TestHelperOz5 contract
        TestHelperOz5.setUp();

        // Provide initial Ether balances to users for testing purposes
        vm.deal(user, 1000 ether);
        vm.deal(blacklistedUser, 1000 ether);

        // Initialize 6 endpoints, using UltraLightNode as the library type
        setUpEndpoints(6, LibraryType.UltraLightNode);

        // Deploy the OTokens, the base token comes first so USDai can read its decimals
        usdtHomeToken = _deployOToken("usdtHomeToken");
        usdtAwayToken = _deployOToken("usdtAwayToken");
        usdaiAwayToken = _deployOToken("usdaiAwayToken");
        stakedUsdaiAwayToken = _deployOToken("stakedUsdaiAwayToken");

        // Deploy the loan router stub used by the StakedUSDai valuation
        mockLoanRouter = new MockLoanRouter();

        // Deploy USDai behind a proxy with the base token fixed and no bridge adapter yet
        USDai usdaiImpl = new USDai(address(usdtHomeToken), address(0), address(0), address(0));
        TransparentUpgradeableProxy usdaiProxy = new TransparentUpgradeableProxy(
            address(usdaiImpl), address(this), abi.encodeWithSignature("initialize(address)", address(this))
        );
        usdai = IUSDai(address(usdaiProxy));

        // Grant the blacklist admin role so the test can mark accounts blacklisted
        AccessControl(address(usdai)).grantRole(keccak256("BLACKLIST_ADMIN_ROLE"), address(this));

        // Deploy StakedUSDai behind a proxy with zero fee rates and no bridge adapter yet
        StakedUSDai stakedUsdaiImpl = new StakedUSDai(
            address(usdai), address(mockLoanRouter), address(this), uint64(block.timestamp), 0, 0, address(0)
        );
        TransparentUpgradeableProxy stakedUsdaiProxy = new TransparentUpgradeableProxy(
            address(stakedUsdaiImpl), address(this), abi.encodeWithSignature("initialize(address)", address(this))
        );
        stakedUsdai = IStakedUSDai(address(stakedUsdaiProxy));

        // Deploy the USDT OAdapters and set their rate limits
        usdtHomeOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(usdtHomeToken), address(endpoints[usdtHomeEid]), address(this))
            )
        );
        usdtAwayOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(usdtAwayToken), address(endpoints[usdtAwayEid]), address(this))
            )
        );
        usdtHomeOAdapter.setRateLimits(_rateLimit(usdtAwayEid));
        usdtAwayOAdapter.setRateLimits(_rateLimit(usdtHomeEid));

        // Deploy the USDai OAdapters and set their rate limits
        usdaiHomeOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode, abi.encode(address(usdai), address(endpoints[usdaiHomeEid]), address(this))
            )
        );
        usdaiAwayOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(usdaiAwayToken), address(endpoints[usdaiAwayEid]), address(this))
            )
        );
        usdaiHomeOAdapter.setRateLimits(_rateLimit(usdaiAwayEid));
        usdaiAwayOAdapter.setRateLimits(_rateLimit(usdaiHomeEid));

        // Deploy the staked USDai OAdapters and set their rate limits
        stakedUsdaiHomeOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(stakedUsdai), address(endpoints[stakedUsdaiHomeEid]), address(this))
            )
        );
        stakedUsdaiAwayOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode,
                abi.encode(address(stakedUsdaiAwayToken), address(endpoints[stakedUsdaiAwayEid]), address(this))
            )
        );
        stakedUsdaiHomeOAdapter.setRateLimits(_rateLimit(stakedUsdaiAwayEid));
        stakedUsdaiAwayOAdapter.setRateLimits(_rateLimit(stakedUsdaiHomeEid));

        // Upgrade USDai to bind the home adapter as its bridge adapter
        usdaiImpl = new USDai(address(usdtHomeToken), address(0), address(0), address(usdaiHomeOAdapter));
        address proxyAdmin = address(uint160(uint256(vm.load(address(usdai), ERC1967Utils.ADMIN_SLOT))));
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(address(usdai)), address(usdaiImpl), "");

        // Upgrade StakedUSDai to bind the home adapter as its bridge adapter
        stakedUsdaiImpl = new StakedUSDai(
            address(usdai),
            address(mockLoanRouter),
            address(this),
            uint64(block.timestamp),
            0,
            0,
            address(stakedUsdaiHomeOAdapter)
        );
        proxyAdmin = address(uint160(uint256(vm.load(address(stakedUsdai), ERC1967Utils.ADMIN_SLOT))));
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(stakedUsdai)), address(stakedUsdaiImpl), ""
        );

        // Bind each OToken to its adapter now that the adapters exist
        _bindOTokenAdapter(usdtHomeToken, address(usdtHomeOAdapter));
        _bindOTokenAdapter(usdtAwayToken, address(usdtAwayOAdapter));
        _bindOTokenAdapter(usdaiAwayToken, address(usdaiAwayOAdapter));
        _bindOTokenAdapter(stakedUsdaiAwayToken, address(stakedUsdaiAwayOAdapter));

        // Configure and wire the OAdapters together
        address[] memory oAdapters = new address[](6);
        oAdapters[0] = address(usdtHomeOAdapter);
        oAdapters[1] = address(usdtAwayOAdapter);
        oAdapters[2] = address(usdaiHomeOAdapter);
        oAdapters[3] = address(usdaiAwayOAdapter);
        oAdapters[4] = address(stakedUsdaiHomeOAdapter);
        oAdapters[5] = address(stakedUsdaiAwayOAdapter);
        this.wireOApps(oAdapters);

        // Deploy the composer utility bound to the base token endpoint
        address[] memory oAdaptersUtility = new address[](2);
        oAdaptersUtility[0] = address(usdtHomeOAdapter);
        oAdaptersUtility[1] = address(usdaiHomeOAdapter);
        OUSDaiUtility oUsdaiUtilityImpl = new OUSDaiUtility(
            address(endpoints[usdtHomeEid]),
            address(usdai),
            address(stakedUsdai),
            address(usdaiHomeOAdapter),
            address(stakedUsdaiHomeOAdapter),
            address(usdtHomeOAdapter)
        );
        TransparentUpgradeableProxy oUsdaiUtilityProxy = new TransparentUpgradeableProxy(
            address(oUsdaiUtilityImpl), address(this), abi.encodeWithSignature("initialize(address)", address(this))
        );
        oUsdaiUtility = OUSDaiUtility(payable(address(oUsdaiUtilityProxy)));

        // Mint tokens to users
        vm.startPrank(address(usdtAwayOAdapter));
        usdtAwayToken.mint(user, initialBalance);
        usdtAwayToken.mint(blacklistedUser, initialBalance);
        vm.stopPrank();
        vm.startPrank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(user, initialBalance);
        vm.stopPrank();

        // Set user as blacklisted
        usdai.setBlacklist(blacklistedUser, true);
    }
}
