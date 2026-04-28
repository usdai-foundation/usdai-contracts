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

import {LoanRouter} from "@usdai-loan-router-contracts/LoanRouter.sol";
import {DepositTimelock} from "@usdai-loan-router-contracts/DepositTimelock.sol";
import {BundleCollateralWrapper} from "@usdai-loan-router-contracts/collateralWrappers/BundleCollateralWrapper.sol";

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

    /* Admin fee rate for loan router (10%) */
    uint256 internal constant LOAN_ROUTER_ADMIN_FEE_RATE = 1000; // 10% in basis points

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

    Users internal users;
    TestERC20 internal usd;
    TestERC20 internal usd2;
    TestERC721 internal nft;
    UniswapV3SwapAdapter internal uniswapV3SwapAdapter;
    BundleCollateralWrapper internal bundleCollateralWrapper;
    DepositTimelock internal depositTimelock;
    LoanRouter internal loanRouter;
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

        deployDepositTimelock();
        deployBundleCollateralWrapper();
        deployLoanRouter();

        deployBaseYieldEscrow();
        deployUniswapV3SwapAdapter();
        deployTestPYUSDPriceFeed();
        deployPriceOracle();
        deployUsdai();
        deployStakedUsdai();
        upgradeUsdai();

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

    function deployBundleCollateralWrapper() internal {
        vm.startPrank(users.deployer);
        bundleCollateralWrapper = new BundleCollateralWrapper();
        vm.stopPrank();
    }

    function deployDepositTimelock() internal {
        vm.startPrank(users.deployer);

        // Deploy implementation
        DepositTimelock depositTimelockImpl = new DepositTimelock();

        // Deploy proxy
        TransparentUpgradeableProxy depositTimelockProxy = new TransparentUpgradeableProxy(
            address(depositTimelockImpl),
            address(users.admin),
            abi.encodeWithSignature("initialize(address)", users.deployer)
        );

        // Create interface
        depositTimelock = DepositTimelock(address(depositTimelockProxy));

        vm.stopPrank();
    }

    function deployLoanRouter() internal {
        vm.startPrank(users.deployer);

        // Deploy implementation
        LoanRouter loanRouterImpl =
            new LoanRouter(address(depositTimelock), ENGLISH_AUCTION_LIQUIDATOR, address(bundleCollateralWrapper));

        // Deploy proxy
        TransparentUpgradeableProxy loanRouterProxy = new TransparentUpgradeableProxy(
            address(loanRouterImpl),
            address(users.admin),
            abi.encodeWithSignature(
                "initialize(address,address,uint256)", users.deployer, users.feeRecipient, LOAN_ROUTER_ADMIN_FEE_RATE
            )
        );

        // Create interface
        loanRouter = LoanRouter(address(loanRouterProxy));

        vm.stopPrank();
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
