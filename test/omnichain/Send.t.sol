// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

// Base imports

// Test imports

// Implementation imports
import {OAdapter} from "src/omnichain/OAdapter.sol";
import {OToken} from "src/omnichain/OToken.sol";

// OApp imports
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import {SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {RateLimiter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

// OZ imports
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Forge imports

// DevTools imports
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract OAdapterSendTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;

    OToken private aToken;
    OToken private bToken;

    OAdapter private aOAdapter;
    OAdapter private bOAdapter;

    address private userA = address(0x1);
    address private userB = address(0x2);
    uint256 private initialBalance = 100 ether;

    function setUp() public virtual override {
        // Provide initial Ether balances to users for testing purposes
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        // Call the base setup function from the TestHelperOz5 contract
        super.setUp();

        // Initialize 2 endpoints, using UltraLightNode as the library type
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Deploy tokens
        OToken aTokenImpl = new OToken(address(0));
        OToken bTokenImpl = new OToken(address(0));

        // Deploy token proxies
        TransparentUpgradeableProxy aTokenProxy = new TransparentUpgradeableProxy(
            address(aTokenImpl),
            address(this),
            abi.encodeWithSignature("initialize(string,string,address)", "aToken", "aToken", address(this))
        );
        TransparentUpgradeableProxy bTokenProxy = new TransparentUpgradeableProxy(
            address(bTokenImpl),
            address(this),
            abi.encodeWithSignature("initialize(string,string,address)", "bToken", "bToken", address(this))
        );
        aToken = OToken(address(aTokenProxy));
        bToken = OToken(address(bTokenProxy));

        RateLimiter.RateLimitConfig[] memory rateLimitConfigsB = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsB[0] = RateLimiter.RateLimitConfig({dstEid: aEid, limit: initialBalance, window: 1 days});

        RateLimiter.RateLimitConfig[] memory rateLimitConfigsA = new RateLimiter.RateLimitConfig[](1);
        rateLimitConfigsA[0] = RateLimiter.RateLimitConfig({dstEid: bEid, limit: initialBalance, window: 1 days});

        // Deploy two instances of OAdapter for testing, associating them with respective endpoints
        aOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode, abi.encode(address(aToken), address(endpoints[aEid]), address(this))
            )
        );

        bOAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode, abi.encode(address(bToken), address(endpoints[bEid]), address(this))
            )
        );

        // Redeploy tokens
        aTokenImpl = new OToken(address(aOAdapter));
        bTokenImpl = new OToken(address(bOAdapter));

        /* Lookup proxy admin from EIP-1967 storage slot */
        address proxyAdmin = address(uint160(uint256(vm.load(address(aToken), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(aToken)),
            address(aTokenImpl),
            "" // No additional initialization data
        );

        /* Lookup proxy admin from EIP-1967 storage slot */
        proxyAdmin = address(uint160(uint256(vm.load(address(bToken), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(bToken)),
            address(bTokenImpl),
            "" // No additional initialization data
        );

        // Configure and wire the OFTs together
        address[] memory ofts = new address[](2);
        ofts[0] = address(aOAdapter);
        ofts[1] = address(bOAdapter);
        this.wireOApps(ofts);

        // Set rate limit configs
        aOAdapter.setRateLimits(rateLimitConfigsA);
        bOAdapter.setRateLimits(rateLimitConfigsB);

        // Mint tokens to users
        vm.startPrank(address(aOAdapter));
        aToken.mint(userA, initialBalance);
        vm.stopPrank();
        vm.startPrank(address(bOAdapter));
        bToken.mint(userB, initialBalance);
        vm.stopPrank();
    }

    // Test the constructor to ensure initial setup and state are correct
    function test__Constructor() public view {
        // Check that the contract owner is correctly set
        assertEq(aOAdapter.owner(), address(this));
        assertEq(bOAdapter.owner(), address(this));

        // Verify initial token balances for userA and userB
        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // Verify that the token address is correctly set to the respective tokens
        assertEq(aOAdapter.token(), address(aToken));
        assertEq(bOAdapter.token(), address(bToken));
    }

    // Test sending tokens from one user to another
    function test__SendOft() public {
        uint256 tokensToSend = 1 ether;

        // Build options for the send operation
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Set up parameters for the send operation
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", "");

        // Quote the fee for sending tokens
        MessagingFee memory fee = aOAdapter.quoteSend(sendParam, false);

        // Verify initial balances before the send operation
        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(bToken.balanceOf(userB), initialBalance);

        // Perform the send operation
        vm.prank(userA);
        aOAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));

        // Verify that the packets were correctly sent to the destination chain.
        // @param _dstEid The endpoint ID of the destination chain.
        // @param _dstAddress The OApp address on the destination chain.
        verifyPackets(bEid, addressToBytes32(address(bOAdapter)));

        // Check balances after the send operation
        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bToken.balanceOf(userB), initialBalance + tokensToSend);
    }
}
