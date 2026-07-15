// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";

contract StakedUSDaiBridgeTest is BaseTest {
    uint256 internal susdaiBalance;

    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), 10_000_000 ether);

        // User deposits USD into USDai
        uint256 usdaiBalance = usdai.deposit(10_000_000 ether, users.normalUser1);

        // User deposits USDai into StakedUSDai
        usdai.approve(address(stakedUsdai), usdaiBalance);
        susdaiBalance = stakedUsdai.deposit(usdaiBalance, users.normalUser1);

        vm.stopPrank();
    }

    function test__StakedUSDaiBridge_Burn() public {
        uint256 totalShares = stakedUsdai.totalShares();
        assertEq(totalShares, susdaiBalance + 1e6);

        vm.startPrank(users.mockOAdapter);
        stakedUsdai.burn(users.normalUser1, 1 ether);
        vm.stopPrank();

        totalShares = stakedUsdai.totalShares();
        assertEq(totalShares, susdaiBalance + 1e6);
    }

    function test__StakedUSDaiBridge_Mint() public {
        vm.startPrank(users.mockOAdapter);
        stakedUsdai.burn(users.normalUser1, 1 ether);
        vm.stopPrank();

        uint256 totalShares = stakedUsdai.totalShares();
        assertEq(totalShares, susdaiBalance + 1e6);

        vm.startPrank(users.mockOAdapter);
        stakedUsdai.mint(users.normalUser1, 1 ether);
        vm.stopPrank();

        totalShares = stakedUsdai.totalShares();
        assertEq(totalShares, susdaiBalance + 1e6);
    }
}
