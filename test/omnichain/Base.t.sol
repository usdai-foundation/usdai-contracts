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

// Mock imports
import {MockUSDai} from "../mocks/MockUSDai.sol";
import {MockStakedUSDai} from "../mocks/MockStakedUSDai.sol";
import {MockLoanRouter} from "../mocks/MockLoanRouter.sol";

// Interface imports
import {IUSDai} from "src/interfaces/IUSDai.sol";
import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";

/**
 * @title Omnichain Base test setup
 * @author USD.AI Foundation
 * @author Modified from https://github.com/PaulRBerg/prb-proxy/blob/main/test/Base.t.sol
 *
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

    uint256 internal initialBalance = 20_000_000 ether;

    IUSDai internal usdai;
    IStakedUSDai internal stakedUsdai;

    address internal user = address(0x1);
    address internal blacklistedUser = address(0x2);

    function setUp() public virtual override {
        // Call the base setup function from the TestHelperOz5 contract
        TestHelperOz5.setUp();

        // Deploy mock USDai
        IUSDai usdaiImpl = new MockUSDai(address(0));

        /* Deploy usdai proxy */
        TransparentUpgradeableProxy usdaiProxy =
            new TransparentUpgradeableProxy(address(usdaiImpl), address(this), abi.encodeWithSignature("initialize()"));

        /* Cast usdai */
        usdai = IUSDai(address(usdaiProxy));

        // Deploy mock loan router
        MockLoanRouter mockLoanRouter = new MockLoanRouter();

        // Deploy mock staked usdai implementation
        IStakedUSDai stakedUsdaiImpl = new MockStakedUSDai(address(usdai), address(mockLoanRouter), address(0));

        /* Deploy staked usdai proxy */
        TransparentUpgradeableProxy stakedUsdaiProxy = new TransparentUpgradeableProxy(
            address(stakedUsdaiImpl), address(this), abi.encodeWithSignature("initialize()")
        );

        /* Cast staked usdai */
        stakedUsdai = IStakedUSDai(address(stakedUsdaiProxy));

        // Provide initial Ether balances to users for testing purposes
        vm.deal(user, 1000 ether);
        vm.deal(blacklistedUser, 1000 ether);

        // Initialize 6 endpoints, using UltraLightNode as the library type
        setUpEndpoints(6, LibraryType.UltraLightNode);

        // Deploy tokens
        OToken usdtHomeTokenImpl = new OToken(address(0));
        OToken usdtAwayTokenImpl = new OToken(address(0));
        OToken usdaiAwayTokenImpl = new OToken(address(0));
        OToken stakedUsdaiAwayTokenImpl = new OToken(address(0));

        // Deploy USDT proxies
        TransparentUpgradeableProxy usdtHomeTokenProxy = new TransparentUpgradeableProxy(
            address(usdtHomeTokenImpl),
            address(this),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "usdtHomeToken", "usdtHomeToken", address(this)
            )
        );
        TransparentUpgradeableProxy usdtAwayTokenProxy = new TransparentUpgradeableProxy(
            address(usdtAwayTokenImpl),
            address(this),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "usdtAwayToken", "usdtAwayToken", address(this)
            )
        );
        TransparentUpgradeableProxy usdaiAwayTokenProxy = new TransparentUpgradeableProxy(
            address(usdaiAwayTokenImpl),
            address(this),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "usdaiAwayToken", "usdaiAwayToken", address(this)
            )
        );
        TransparentUpgradeableProxy stakedUsdaiAwayTokenProxy = new TransparentUpgradeableProxy(
            address(stakedUsdaiAwayTokenImpl),
            address(this),
            abi.encodeWithSignature(
                "initialize(string,string,address)", "stakedUsdaiAwayToken", "stakedUsdaiAwayToken", address(this)
            )
        );
        usdtHomeToken = OToken(address(usdtHomeTokenProxy));
        usdtAwayToken = OToken(address(usdtAwayTokenProxy));
        usdaiAwayToken = OToken(address(usdaiAwayTokenProxy));
        stakedUsdaiAwayToken = OToken(address(stakedUsdaiAwayTokenProxy));

        // Deploy USDT rate limit configs
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsUsdtHome = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsUsdtHome[0] =
            RateLimiter.RateLimitConfig({dstEid: usdtAwayEid, limit: initialBalance, window: 1 days});
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsUsdtAway = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsUsdtAway[0] =
            RateLimiter.RateLimitConfig({dstEid: usdtHomeEid, limit: initialBalance, window: 1 days});

        // Deploy USDAI rate limit configs
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsUsdaiHome = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsUsdaiHome[0] =
            RateLimiter.RateLimitConfig({dstEid: usdaiAwayEid, limit: initialBalance, window: 1 days});
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsUsdaiAway = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsUsdaiAway[0] =
            RateLimiter.RateLimitConfig({dstEid: usdaiHomeEid, limit: initialBalance, window: 1 days});

        // Deploy staked USDAI rate limit configs
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsStakedUsdaiHome = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsStakedUsdaiHome[0] =
            RateLimiter.RateLimitConfig({dstEid: stakedUsdaiAwayEid, limit: initialBalance, window: 1 days});
        RateLimiter.RateLimitConfig[] memory rateLimitConfigsStakedUsdaiAway = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsStakedUsdaiAway[0] =
            RateLimiter.RateLimitConfig({dstEid: stakedUsdaiHomeEid, limit: initialBalance, window: 1 days});

        // Deploy two instances of USDT OAdapter for testing, associating them with respective endpoints
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
        usdtHomeOAdapter.setRateLimits(rateLimitConfigsUsdtHome);
        usdtAwayOAdapter.setRateLimits(rateLimitConfigsUsdtAway);

        // Deploy two instances of USDAI OAdapter for testing, associating them with respective endpoints
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
        usdaiHomeOAdapter.setRateLimits(rateLimitConfigsUsdaiHome);
        usdaiAwayOAdapter.setRateLimits(rateLimitConfigsUsdaiAway);

        // Deploy two instances of staked USDAI OAdapter for testing, associating them with respective endpoints
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
        stakedUsdaiHomeOAdapter.setRateLimits(rateLimitConfigsStakedUsdaiHome);
        stakedUsdaiAwayOAdapter.setRateLimits(rateLimitConfigsStakedUsdaiAway);

        /* Deploy usdai implementation */
        usdaiImpl = new MockUSDai(address(usdaiHomeOAdapter));

        /* Lookup proxy admin from EIP-1967 storage slot */
        address proxyAdmin = address(uint160(uint256(vm.load(address(usdai), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(usdai)),
            address(usdaiImpl),
            "" // No additional initialization data
        );

        /* Set the USDai base token to the USDT home token */
        MockUSDai(address(usdai)).setBaseToken(address(usdtHomeToken));

        /* Deploy staked usdai implementation */
        stakedUsdaiImpl = new MockStakedUSDai(address(usdai), address(mockLoanRouter), address(stakedUsdaiHomeOAdapter));

        /* Lookup proxy admin from EIP-1967 storage slot */
        proxyAdmin = address(uint160(uint256(vm.load(address(stakedUsdai), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(stakedUsdai)),
            address(stakedUsdaiImpl),
            "" // No additional initialization data
        );

        /* Deploy staked usdai implementation */
        stakedUsdaiImpl = new MockStakedUSDai(address(usdai), address(mockLoanRouter), address(stakedUsdaiHomeOAdapter));

        /* Lookup proxy admin from EIP-1967 storage slot */
        proxyAdmin = address(uint160(uint256(vm.load(address(stakedUsdai), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(stakedUsdai)),
            address(stakedUsdaiImpl),
            "" // No additional initialization data
        );

        // Redeploy omnichain tokens
        usdtHomeTokenImpl = new OToken(address(usdtHomeOAdapter));
        usdtAwayTokenImpl = new OToken(address(usdtAwayOAdapter));
        usdaiAwayTokenImpl = new OToken(address(usdaiAwayOAdapter));
        stakedUsdaiAwayTokenImpl = new OToken(address(stakedUsdaiAwayOAdapter));

        /* Lookup proxy admin from EIP-1967 storage slot */
        proxyAdmin = address(uint160(uint256(vm.load(address(usdtHomeToken), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(usdtHomeToken)),
            address(usdtHomeTokenImpl),
            "" // No additional initialization data
        );

        /* Lookup proxy admin from EIP-1967 storage slot */
        proxyAdmin = address(uint160(uint256(vm.load(address(usdtAwayToken), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(usdtAwayToken)),
            address(usdtAwayTokenImpl),
            "" // No additional initialization data
        );

        /* Lookup proxy admin from EIP-1967 storage slot */
        proxyAdmin = address(uint160(uint256(vm.load(address(usdaiAwayToken), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(usdaiAwayToken)),
            address(usdaiAwayTokenImpl),
            "" // No additional initialization data
        );

        /* Lookup proxy admin from EIP-1967 storage slot */
        proxyAdmin = address(uint160(uint256(vm.load(address(stakedUsdaiAwayToken), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(stakedUsdaiAwayToken)),
            address(stakedUsdaiAwayTokenImpl),
            "" // No additional initialization data
        );

        // Configure and wire the USDT OAdapters together
        address[] memory oAdapters = new address[](6);
        oAdapters[0] = address(usdtHomeOAdapter);
        oAdapters[1] = address(usdtAwayOAdapter);
        oAdapters[2] = address(usdaiHomeOAdapter);
        oAdapters[3] = address(usdaiAwayOAdapter);
        oAdapters[4] = address(stakedUsdaiHomeOAdapter);
        oAdapters[5] = address(stakedUsdaiAwayOAdapter);
        this.wireOApps(oAdapters);

        // Deploy the composer receiver
        address[] memory oAdaptersUtility = new address[](2);
        oAdaptersUtility[0] = address(usdtHomeOAdapter);
        oAdaptersUtility[1] = address(usdaiHomeOAdapter);
        OUSDaiUtility oUsdaiUtilityImpl = new OUSDaiUtility(
            address(endpoints[usdtHomeEid]),
            address(usdai),
            address(stakedUsdai),
            address(usdaiHomeOAdapter),
            address(stakedUsdaiHomeOAdapter)
        );
        TransparentUpgradeableProxy oUsdaiUtilityProxy = new TransparentUpgradeableProxy(
            address(oUsdaiUtilityImpl),
            address(this),
            abi.encodeWithSignature("initialize(address,address[])", address(this), oAdaptersUtility)
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
        AccessControl(address(stakedUsdai)).grantRole(keccak256("BLACKLIST_ADMIN_ROLE"), address(this));
        usdai.setBlacklist(blacklistedUser, true);
    }
}
