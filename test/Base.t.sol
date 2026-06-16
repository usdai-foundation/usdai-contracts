// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {TestERC721} from "./tokens/TestERC721.sol";
import {TestERC20} from "./tokens/TestERC20.sol";

import {UniswapPoolHelpers} from "./helpers/UniswapPoolHelpers.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ICollateralTimelock} from "@usdai-loan-router-contracts/interfaces/ICollateralTimelock.sol";
import {IEscrowTimelock} from "@usdai-loan-router-contracts/interfaces/IEscrowTimelock.sol";
import {IDepositTimelock} from "@usdai-loan-router-contracts/interfaces/IDepositTimelock.sol";
import {IEscrowTimelock} from "@usdai-loan-router-contracts/interfaces/IEscrowTimelock.sol";
import {ILoanRouterV2} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2.sol";

import {USDai} from "src/USDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {BaseYieldEscrow} from "src/BaseYieldEscrow.sol";
import {ChainlinkPriceOracle} from "src/oracles/ChainlinkPriceOracle.sol";
import {UniswapV3SwapAdapter} from "src/swapAdapters/UniswapV3SwapAdapter.sol";
import {IUSDai} from "src/interfaces/IUSDai.sol";

import {TestPYUSDPriceFeed} from "../script/DeployTestPYUSDPriceFeed.s.sol";

/**
 * @title Base test setup
 *
 * @author USD.AI Foundation
 * @author Modified from https://github.com/PaulRBerg/prb-proxy/blob/main/test/Base.t.sol
 *
 * @dev Sets up users and token contracts
 */
abstract contract BaseTest is Test {
    /* PYUSD OFT adapter */
    address internal constant PYUSD_OFT_ADAPTER = 0xFaB5891ED867a1195303251912013b92c4fc3a1D;

    /* PYUSD */
    IERC20 internal constant PYUSD = IERC20(0x46850aD61C2B7d64d08c9C754F45254596696984);

    /* PYUSD price feed on Ethereum */
    address internal constant PYUSD_PRICE_FEED = 0x3d50d699A812A0f66F36876DF47B2aE68e781736;

    /* Fixed point scale */
    uint256 internal constant FIXED_POINT_SCALE = 1e18;

    /* Basis points scale */
    uint256 internal constant BASIS_POINTS_SCALE = 10_000;

    /* Locked shares */
    uint128 internal constant LOCKED_SHARES = 1e6;

    /* Admin fee rate for loan router (1%), matches deployStakedUsdai() constructor arg */
    uint256 internal constant LOAN_ROUTER_ADMIN_FEE_RATE = 100; // 1% in basis points

    /* APR 4.5% to daily interest rate = 4.5% * 1e18 / (365 * 86400) = 1426940639 (scaled by 1e18)  */
    uint256 internal constant BASE_YIELD_RATE_1 = 1426940639;

    /* APR 3.5% to daily interest rate = 3.5% * 1e18 / (365 * 86400) = 1109842719 (scaled by 1e18)  */
    uint256 internal constant BASE_YIELD_RATE_2 = 1109842719;

    /* Base yield cutoff = 1,000,000,000 USD */
    uint256 internal constant BASE_YIELD_CUTOFF_1 = 1_000_000_000 ether;

    /* Base yield cutoff = type(uint256).max */
    uint256 internal constant BASE_YIELD_CUTOFF_2 = type(uint256).max;

    /* WETH */
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /* USDT */
    address internal constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    /* USDC */
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    /* WETH price feed */
    address internal constant WETH_PRICE_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    /* USDT price feed */
    address internal constant USDT_PRICE_FEED = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;

    /* USDC price feed */
    address internal constant USDC_PRICE_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    /* L2 sequencer uptime feed (Arbitrum) */
    address internal constant SEQUENCER_UPTIME_FEED = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    /* English auction liquidator */
    address internal constant ENGLISH_AUCTION_LIQUIDATOR = 0xceb5856C525bbb654EEA75A8852A0F51073C4a58;

    /**
     * @notice User accounts
     */
    struct Users {
        address payable deployer;
        address payable normalUser1;
        address payable normalUser2;
        address payable admin;
        address payable manager;
        address payable feeRecipient;
        address payable borrower;
        address payable mockOAdapter;
    }

    /* Mirror of a .bytecode.linkReferences entry. Fields ordered alphabetically for JSON decoding. */
    struct LinkReference {
        uint256 length;
        uint256 start;
    }

    Users internal users;
    TestERC20 internal usd;
    TestERC20 internal usd2;
    TestERC721 internal nft;
    UniswapV3SwapAdapter internal uniswapV3SwapAdapter;
    ICollateralTimelock internal collateralTimelock;
    IDepositTimelock internal depositTimelock;
    IEscrowTimelock internal escrowTimelock;
    ILoanRouterV2 internal loanRouter;
    BaseYieldEscrow internal baseYieldEscrow;
    ChainlinkPriceOracle internal priceOracle;
    IUSDai internal usdai;
    StakedUSDai internal stakedUsdai;
    TestPYUSDPriceFeed internal testPYUSDPriceFeed;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.rollFork(333898546);

        users = Users({
            deployer: createUser("deployer"),
            normalUser1: createUser("normalUser1"),
            normalUser2: createUser("normalUser2"),
            admin: createUser("admin"),
            manager: createUser("manager"),
            feeRecipient: createUser("feeRecipient"),
            borrower: createUser("borrower"),
            mockOAdapter: createUser("mockOAdapter")
        });

        /* Fund users */
        fundUsers();

        /* Deploy contracts */
        deployNft();
        deployUsd();
        deployUsdPool();

        deployBaseYieldEscrow();
        deployUniswapV3SwapAdapter();
        deployTestPYUSDPriceFeed();
        deployPriceOracle();
        deployUsdai();

        deployCollateralTimelock();
        deployEscrowTimelock();
        deployDepositTimelock();
        deployLoanRouter();

        deployStakedUsdai();
        upgradeUsdai();

        grantDepositTimelockRoles();
        grantCollateralTimelockRoles();

        setupPyusdLiquidity();

        /* Set approvals */
        setApprovals();
    }

    function setupPyusdLiquidity() internal {
        /* Mint to admin */
        deal(address(PYUSD), address(users.admin), 40_000_002 ether);
        deal(address(USDC), address(users.admin), 20_000_001 ether);

        /* Deploy pool as admin */
        vm.startPrank(users.admin);
        UniswapPoolHelpers.setupUniswapPool(
            address(users.admin), address(usd), address(PYUSD), 20_000_000 ether, 20_000_000 ether
        );
        UniswapPoolHelpers.setupUniswapPool(
            address(users.admin), address(USDC), address(PYUSD), 20_000_000 ether, 20_000_000 ether
        );
        vm.stopPrank();
    }

    function deployUniswapV3SwapAdapter() internal {
        vm.startPrank(users.deployer);

        address[] memory whitelistedTokens = new address[](4);
        whitelistedTokens[0] = address(usd);
        whitelistedTokens[1] = address(WETH);
        whitelistedTokens[2] = address(USDT);
        whitelistedTokens[3] = address(USDC);

        /* Deploy Uniswap V3 swap adapter */
        uniswapV3SwapAdapter =
            new UniswapV3SwapAdapter(address(PYUSD), address(UniswapPoolHelpers.UNISWAP_ROUTER), whitelistedTokens);

        vm.stopPrank();
    }

    function deployTestPYUSDPriceFeed() internal {
        vm.startPrank(users.deployer);

        /* Deploy mock m chainlink oracle */
        testPYUSDPriceFeed = new TestPYUSDPriceFeed();

        vm.stopPrank();
    }

    function deployBaseYieldEscrow() internal {
        vm.startPrank(users.deployer);

        /* Deploy base token yield escrow */
        BaseYieldEscrow baseYieldEscrowImpl = new BaseYieldEscrow(address(0), address(PYUSD));
        TransparentUpgradeableProxy baseYieldEscrowProxy = new TransparentUpgradeableProxy(
            address(baseYieldEscrowImpl),
            address(users.admin),
            abi.encodeWithSignature("initialize(address)", users.admin)
        );
        baseYieldEscrow = BaseYieldEscrow(address(baseYieldEscrowProxy));

        vm.stopPrank();

        /* Grant roles */
        vm.startPrank(users.admin);
        baseYieldEscrow.grantRole(keccak256("ESCROW_ADMIN_ROLE"), address(users.admin));
        baseYieldEscrow.grantRole(keccak256("RATE_ADMIN_ROLE"), address(users.admin));

        /* Fund admin */
        deal(address(PYUSD), users.admin, 50_000_000 ether);

        vm.startPrank(users.admin);

        /* Deposit PYUSD into base yield escrow */
        PYUSD.approve(address(baseYieldEscrow), 50_000_000 ether);
        baseYieldEscrow.deposit(50_000_000 ether);

        vm.stopPrank();
    }

    function deployNft() internal {
        vm.startPrank(users.deployer);

        /* Deploy NFT */
        nft = new TestERC721("NFT", "NFT", "https://nft1.com/token/");

        /* Mint NFT to users */
        nft.mint(address(users.normalUser1), 123);
        nft.mint(address(users.normalUser2), 124);

        vm.stopPrank();
    }

    function deployUsd() internal {
        vm.startPrank(users.deployer);

        /* Deploy USD ERC20 */
        usd = new TestERC20("USD", "USD", 6, 300_000_000 ether);

        /* Mint USD to users */
        /// forge-lint: disable-next-line
        usd.transfer(address(users.normalUser1), 40_000_000 ether);
        /// forge-lint: disable-next-line
        usd.transfer(address(users.normalUser2), 40_000_000 ether);
        /// forge-lint: disable-next-line
        usd.transfer(address(users.admin), 50_000_000 ether);
        /// forge-lint: disable-next-line
        usd.transfer(address(users.manager), 40_000_000 ether);

        /* Deploy USD2 ERC20 */
        usd2 = new TestERC20("USD", "USD", 6, 300_000_000 ether);

        /* Mint USD2 to users */
        /// forge-lint: disable-next-line
        usd2.transfer(address(users.normalUser1), 40_000_000 ether);
        /// forge-lint: disable-next-line
        usd2.transfer(address(users.normalUser2), 40_000_000 ether);
        /// forge-lint: disable-next-line
        usd2.transfer(address(users.admin), 50_000_000 ether);
        /// forge-lint: disable-next-line
        usd2.transfer(address(users.manager), 40_000_000 ether);

        vm.stopPrank();
    }

    function deployUsdPool() internal {
        vm.startPrank(users.admin);

        UniswapPoolHelpers.setupUniswapPool(
            address(users.admin), address(usd), address(usd2), 20_000_000 ether, 20_000_000 ether
        );

        UniswapPoolHelpers.setupUniswapPool(
            address(users.admin), address(usd), address(USDT), 1_000_000 * 1e6, 1_000_000 * 1e6
        );

        vm.stopPrank();
    }

    function deployUsdai() internal {
        vm.startPrank(users.deployer);

        /* Deploy usdai implementation */
        IUSDai usdaiImpl =
            new USDai(address(uniswapV3SwapAdapter), address(baseYieldEscrow), address(stakedUsdai), users.mockOAdapter);

        /* Deploy usdai proxy */
        TransparentUpgradeableProxy usdaiProxy = new TransparentUpgradeableProxy(
            address(usdaiImpl), address(users.admin), abi.encodeWithSignature("initialize(address)", users.deployer)
        );

        /* Deploy usdai */
        usdai = IUSDai(address(usdaiProxy));

        /* Grant USDai role to Uniswap V3 swap adapter */
        uniswapV3SwapAdapter.grantRole(keccak256("USDAI_ROLE"), address(usdai));

        /* Grant blacklist admin role to deployer */
        AccessControl(address(usdai)).grantRole(keccak256("BLACKLIST_ADMIN_ROLE"), address(users.deployer));

        vm.stopPrank();

        vm.prank(users.admin);
        baseYieldEscrow.grantRole(keccak256("HARVEST_ADMIN_ROLE"), address(usdai));

        /* Deploy base yield escrow implementation */
        BaseYieldEscrow baseYieldEscrowImpl = new BaseYieldEscrow(address(usdai), address(PYUSD));

        /* Lookup proxy admin from EIP-1967 storage slot */
        address proxyAdmin = address(uint160(uint256(vm.load(address(baseYieldEscrow), ERC1967Utils.ADMIN_SLOT))));

        vm.prank(users.admin);

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(baseYieldEscrow)),
            address(baseYieldEscrowImpl),
            "" // No additional initialization data
        );
        vm.stopPrank();
    }

    function upgradeUsdai() internal {
        /* Deploy usdai implementation */
        IUSDai usdaiImpl =
            new USDai(address(uniswapV3SwapAdapter), address(baseYieldEscrow), address(stakedUsdai), users.mockOAdapter);

        /* Lookup proxy admin from EIP-1967 storage slot */
        address proxyAdmin = address(uint160(uint256(vm.load(address(usdai), ERC1967Utils.ADMIN_SLOT))));

        vm.prank(users.admin);

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(usdai)),
            address(usdaiImpl),
            "" // No additional initialization data
        );
        vm.stopPrank();
    }

    function deployPriceOracle() internal {
        vm.startPrank(users.deployer);

        /* Deploy staked usdai implementation */
        address[] memory tokens = new address[](3);
        tokens[0] = address(WETH);
        tokens[1] = address(USDT);
        tokens[2] = address(USDC);
        address[] memory priceFeeds = new address[](3);
        priceFeeds[0] = address(WETH_PRICE_FEED);
        priceFeeds[1] = address(USDT_PRICE_FEED);
        priceFeeds[2] = address(USDC_PRICE_FEED);
        priceOracle = new ChainlinkPriceOracle(
            SEQUENCER_UPTIME_FEED, address(testPYUSDPriceFeed), tokens, priceFeeds, users.admin
        );

        vm.stopPrank();
    }

    function deployStakedUsdai() internal {
        vm.startPrank(users.deployer);

        /* Deploy staked usdai implementation */
        StakedUSDai stakedUsdaiImpl = new StakedUSDai(
            address(usdai),
            address(priceOracle),
            address(loanRouter),
            address(users.admin),
            uint64(block.timestamp),
            100,
            100,
            users.mockOAdapter
        );

        /* Deploy staked usdai proxy */
        TransparentUpgradeableProxy stakedUsdaiProxy = new TransparentUpgradeableProxy(
            address(stakedUsdaiImpl),
            address(users.admin),
            abi.encodeWithSignature("initialize(address)", users.deployer)
        );

        /* Deploy staked usdai */
        stakedUsdai = StakedUSDai(address(stakedUsdaiProxy));

        /* Grant roles */
        stakedUsdai.grantRole(keccak256("BLACKLIST_ADMIN_ROLE"), address(users.deployer));
        stakedUsdai.grantRole(keccak256("PAUSE_ADMIN_ROLE"), address(users.deployer));
        stakedUsdai.grantRole(keccak256("STRATEGY_ADMIN_ROLE"), address(users.manager));

        /* Grant bridge admin role to manager only for testing */
        stakedUsdai.grantRole(keccak256("BRIDGE_ADMIN_ROLE"), address(users.manager));

        /* Grant base yield recipient role to staked USDai */
        AccessControl(address(usdai)).grantRole(keccak256("BASE_YIELD_RECIPIENT_ROLE"), address(stakedUsdai));

        vm.stopPrank();
    }

    function deployEscrowTimelock() internal {
        string memory json;
        try vm.readFile("externalOut/EscrowTimelock.sol/EscrowTimelock.json") returns (string memory content) {
            json = content;
        } catch {
            revert(
                "EscrowTimelock artifact not found in externalOut/. Run: FOUNDRY_OUT=$(pwd)/externalOut forge build --root lib/usdai-loan-router-contracts"
            );
        }

        uint64 nonce = vm.getNonce(users.deployer);
        // escrow impl +0, escrow proxy +1, deposit impl +2, deposit proxy +3,
        // loanRouter proxy +4, stakedUsdai impl +5, stakedUsdai proxy +6
        address futureDepositor = vm.computeCreateAddress(users.deployer, nonce + 6);

        bytes memory initCode = abi.encodePacked(
            vm.parseJsonBytes(json, ".bytecode.object"), abi.encode(address(usdai), futureDepositor, users.admin)
        );

        vm.startPrank(users.deployer);

        address impl;
        assembly {
            impl := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(impl != address(0), "EscrowTimelock implementation deployment failed");

        escrowTimelock = IEscrowTimelock(
            address(new ERC1967Proxy(impl, abi.encodeWithSignature("initialize(address)", users.admin)))
        );

        vm.stopPrank();
    }

    function grantEscrowTimelockRoles() internal {
        /* Sanity check deployment wiring */
        require(
            ILoanRouterV2(address(loanRouter)).escrowTimelock() == address(escrowTimelock),
            "escrowTimelock address mismatch in loanRouter"
        );
        require(escrowTimelock.depositor() == address(stakedUsdai), "escrowTimelock depositor mismatch");

        /* Fund admin with USDai so it can cover interest on cancel and withdraw */
        vm.startPrank(users.manager);
        usd.approve(address(usdai), 10_000 ether);
        usdai.deposit(address(usd), 10_000 ether, 1, users.admin);
        vm.stopPrank();

        vm.startPrank(users.admin);
        /* Admin approves escrowTimelock to pull USDai back (principal return + interest) */
        IERC20(address(usdai)).approve(address(escrowTimelock), type(uint256).max);
        vm.stopPrank();
    }

    function deployCollateralTimelock() internal {
        string memory artifactPath = "externalOut/CollateralTimelock.sol/CollateralTimelock.json";

        string memory json;
        try vm.readFile(artifactPath) returns (string memory content) {
            json = content;
        } catch {
            revert(
                "CollateralTimelock artifact not found in externalOut/. Run: FOUNDRY_OUT=$(pwd)/externalOut forge build --root lib/usdai-loan-router-contracts"
            );
        }

        bytes memory initCode = abi.encodePacked(vm.parseJsonBytes(json, ".bytecode.object"));

        vm.startPrank(users.deployer);

        address impl;
        assembly {
            impl := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(impl != address(0), "CollateralTimelock implementation deployment failed");

        collateralTimelock = ICollateralTimelock(
            address(new ERC1967Proxy(impl, abi.encodeWithSignature("initialize(address)", users.admin)))
        );

        vm.stopPrank();
    }

    function deployDepositTimelock() internal {
        string memory artifactPath = "externalOut/DepositTimelock.sol/DepositTimelock.json";

        string memory json;
        try vm.readFile(artifactPath) returns (string memory content) {
            json = content;
        } catch {
            revert(
                "DepositTimelock artifact not found in externalOut/. Run: FOUNDRY_OUT=$(pwd)/externalOut forge build --root lib/usdai-loan-router-contracts"
            );
        }

        bytes memory initCode =
            abi.encodePacked(vm.parseJsonBytes(json, ".bytecode.object"), abi.encode(address(usdai)));

        vm.startPrank(users.deployer);

        address impl;
        assembly {
            impl := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(impl != address(0), "DepositTimelock implementation deployment failed");

        depositTimelock = IDepositTimelock(
            address(new ERC1967Proxy(impl, abi.encodeWithSignature("initialize(address)", users.admin)))
        );

        vm.stopPrank();
    }

    function grantDepositTimelockRoles() internal {
        vm.prank(users.admin);
        AccessControl(address(depositTimelock)).grantRole(keccak256("DEPOSITOR_ROLE"), address(stakedUsdai));
    }

    function grantCollateralTimelockRoles() internal {
        vm.prank(users.admin);
        AccessControl(address(collateralTimelock)).grantRole(keccak256("DEPOSITOR_ROLE"), address(users.borrower));
    }

    function deployLoanRouter() internal {
        /* Read artifacts — existence check on the primary artifact */
        string memory routerJson;
        try vm.readFile("externalOut/LoanRouterV2.sol/LoanRouterV2.json") returns (string memory content) {
            routerJson = content;
        } catch {
            revert(
                "LoanRouterV2 artifact not found in externalOut/. Run: FOUNDRY_OUT=$(pwd)/externalOut forge build --root lib/usdai-loan-router-contracts"
            );
        }

        /* Deploy ScheduleLogic (no link references) */
        address scheduleLogicLib = _deployFromHex(
            vm.parseJsonString(vm.readFile("externalOut/ScheduleLogic.sol/ScheduleLogic.json"), ".bytecode.object"), ""
        );

        /* Deploy LoanLogicV2 (links: ScheduleLogic) */
        string memory loanLogicJson = vm.readFile("externalOut/LoanLogicV2.sol/LoanLogicV2.json");
        bytes memory llHex = bytes(vm.parseJsonString(loanLogicJson, ".bytecode.object"));
        _linkLibrary(llHex, loanLogicJson, "src/ScheduleLogic.sol", "ScheduleLogic", scheduleLogicLib);
        address loanLogicLib = _deployFromHex(string(llHex), "");

        /* Link and deploy LoanRouterV2 implementation */
        bytes memory lrHex = bytes(vm.parseJsonString(routerJson, ".bytecode.object"));
        _linkLibrary(lrHex, routerJson, "src/LoanLogicV2.sol", "LoanLogicV2", loanLogicLib);
        _linkLibrary(lrHex, routerJson, "src/ScheduleLogic.sol", "ScheduleLogic", scheduleLogicLib);

        /* Constructor args: (feeRecipient_, collateralTimelock_, depositTimelock_, escrowTimelock_) */
        address impl = _deployFromHex(
            string(lrHex),
            abi.encode(
                users.feeRecipient, address(collateralTimelock), address(depositTimelock), address(escrowTimelock)
            )
        );

        vm.startPrank(users.deployer);

        loanRouter =
            ILoanRouterV2(address(new ERC1967Proxy(impl, abi.encodeWithSignature("initialize(address)", users.admin))));

        vm.stopPrank();
    }

    /**
     * @notice Decode a hex string and deploy it with optional constructor args appended.
     */
    function _deployFromHex(string memory hexStr, bytes memory constructorArgs) internal returns (address addr) {
        bytes memory code = abi.encodePacked(_fromHex(bytes(hexStr)), constructorArgs);
        assembly {
            addr := create(0, add(code, 0x20), mload(code))
        }
        require(addr != address(0), "deployment failed");
    }

    /**
     * @notice Link every placeholder for `contractName` defined in `sourcePath` by reading the
     *         start offsets from the artifact's .bytecode.linkReferences and overwriting them with `lib`.
     */
    function _linkLibrary(
        bytes memory hexStr,
        string memory artifactJson,
        string memory sourcePath,
        string memory contractName,
        address lib
    ) internal pure {
        string memory key = string.concat(".bytecode.linkReferences['", sourcePath, "']['", contractName, "']");
        /* Forge decodes JSON object keys alphabetically, so fields must stay ordered length then start. */
        LinkReference[] memory refs = abi.decode(vm.parseJson(artifactJson, key), (LinkReference[]));
        for (uint256 i; i < refs.length; i++) {
            _writeAddrHex(hexStr, refs[i].start, lib);
        }
    }

    /**
     * @notice Overwrite 40 hex chars in a bytecode hex string at byte offset `byteOffset`
     *         with the lowercase hex of `lib`. Used to link library placeholders.
     */
    function _writeAddrHex(bytes memory hexStr, uint256 byteOffset, address lib) internal pure {
        uint256 pos = 2 + byteOffset * 2; // skip leading "0x"
        bytes20 a = bytes20(lib);
        for (uint256 i; i < 20; i++) {
            uint8 hi = uint8(a[i]) >> 4;
            uint8 lo = uint8(a[i]) & 0xf;
            hexStr[pos + i * 2] = bytes1(hi < 10 ? hi + 48 : hi + 87);
            hexStr[pos + i * 2 + 1] = bytes1(lo < 10 ? lo + 48 : lo + 87);
        }
    }

    /**
     * @notice Decode a "0x..."-prefixed hex string to bytes.
     */
    function _fromHex(
        bytes memory h
    ) internal pure returns (bytes memory result) {
        result = new bytes((h.length - 2) / 2);
        for (uint256 i; i < result.length; i++) {
            result[i] = bytes1((_hexNibble(h[2 + i * 2]) << 4) | _hexNibble(h[2 + i * 2 + 1]));
        }
    }

    function _hexNibble(
        bytes1 c
    ) internal pure returns (uint8) {
        uint8 v = uint8(c);
        if (v >= 48 && v <= 57) return v - 48;
        if (v >= 97 && v <= 102) return v - 87;
        if (v >= 65 && v <= 70) return v - 55;
        revert("_hexNibble: invalid char");
    }

    function fundUsers() internal {
        // Fund WETH holders
        deal(address(WETH), address(users.admin), 10_000 ether);
        deal(address(WETH), address(users.normalUser1), 2_000 ether);
        deal(address(WETH), address(users.normalUser2), 2_000 ether);

        // Fund USDT holders
        deal(address(USDT), address(users.admin), 10_000_000 * 1e6);

        // Fund USDC holders
        deal(USDC, users.borrower, 10_000_000 * 1e6);
    }

    function createUser(
        string memory name
    ) internal returns (address payable addr) {
        addr = payable(makeAddr(name));
        vm.label({account: addr, newLabel: name});
        vm.deal({account: addr, newBalance: 100 ether});
    }

    function setApprovals() internal {
        address[] memory normalUsers = new address[](2);
        normalUsers[0] = users.normalUser1;
        normalUsers[1] = users.normalUser2;

        for (uint256 i = 0; i < normalUsers.length; i++) {
            vm.startPrank(normalUsers[i]);

            /* Approve tokens */
            usd.approve(address(usdai), type(uint256).max);
            usdai.approve(address(stakedUsdai), type(uint256).max);

            vm.stopPrank();
        }
    }

    function simulateYieldDeposit(
        uint256 amount
    ) internal {
        vm.startPrank(users.manager);
        usd.approve(address(usdai), amount * 2);

        // User deposits USD into USDai
        usdai.deposit(address(usd), amount * 2, amount, address(users.manager));

        /* Deposit into staked usdai */
        usdai.transfer(address(stakedUsdai), amount);

        vm.stopPrank();

        bytes32 depositsStorageLocation = 0x2c5de62bb029e52f8f5651820547ac44294b098c752111b71e5fee4f80a66900;
        uint256 currentBalance = uint256(vm.load(address(stakedUsdai), depositsStorageLocation));
        vm.store(address(stakedUsdai), depositsStorageLocation, bytes32(currentBalance + amount));
    }

    function serviceRedemptionAndWarp(uint256 requestedShares, bool warp) internal returns (uint256) {
        vm.startPrank(users.manager);

        // Get redemption timestamp
        uint64 redemptionTimestamp = stakedUsdai.redemptionTimestamp();

        // Warp past redemption timestamp
        if (warp) {
            vm.warp(redemptionTimestamp + 30 days);
        }

        /* Harvest base yield */
        stakedUsdai.harvestBaseYield();

        uint256 amountProcessed = stakedUsdai.serviceRedemptions(requestedShares);

        vm.stopPrank();

        return amountProcessed;
    }
}
