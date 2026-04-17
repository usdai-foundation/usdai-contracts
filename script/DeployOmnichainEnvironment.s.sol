// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {OToken} from "src/omnichain/OToken.sol";
import {OAdapter} from "src/omnichain/OAdapter.sol";

import {Deployer} from "./utils/Deployer.s.sol";

interface ICreateX {
    function computeCreate3Address(
        bytes32 salt
    ) external view returns (address computedAddress);
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
}

contract DeployOmnichainEnvironment is Deployer {
    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address internal constant USDAI_ADDRESS = 0x0A1a1A107E45b7Ced86833863f482BC5f4ed82EF;
    address internal constant STAKED_USDAI_ADDRESS = 0x0B2b2B2076d95dda7817e785989fE353fe955ef9;
    bytes32 internal constant USDAI_SALT = 0x783B08aA21DE056717173f72E04Be0E91328A07b00183935ad8e5347035b83b1;
    bytes32 internal constant STAKED_USDAI_SALT = 0x783B08aA21DE056717173f72E04Be0E91328A07b003da1d5d1f7b6bd037eb47d;

    address internal constant OADAPTER_USDAI_ADDRESS = 0xffA10065Ce1d1C42FABc46e06B84Ed8FfEb4baE5;
    address internal constant OADAPTER_STAKED_USDAI_ADDRESS = 0xffB20098FD7B8E84762eea4609F299D101427f24;
    bytes32 internal constant OADAPTER_USDAI_SALT = 0x783b08aa21de056717173f72e04be0e91328a07b002c1b8e24ad605a030eb3d0;
    bytes32 internal constant OADAPTER_STAKED_USDAI_SALT =
        0x783b08aa21de056717173f72e04be0e91328a07b00e790759c9fc3980368de62;

    function run(address deployer, address lzEndpoint, address multisig) public broadcast useDeployment {
        // Deploy OToken implemetation
        OToken usdaiOtokenImpl = new OToken(OADAPTER_USDAI_ADDRESS);
        OToken stakedUSDaiOtokenImpl = new OToken(OADAPTER_STAKED_USDAI_ADDRESS);

        // Prepare Create3 Calldata for OToken USDai
        if (CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, USDAI_SALT))) != USDAI_ADDRESS) {
            revert InvalidParameter();
        }
        bytes memory otokenUSDaiCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            USDAI_SALT,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(
                    address(usdaiOtokenImpl),
                    deployer,
                    abi.encodeWithSelector(OToken.initialize.selector, "USDai", "USDai", multisig)
                )
            )
        );

        // Prepare Create3 Calldata for OToken StakedUSDai
        if (CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, STAKED_USDAI_SALT))) != STAKED_USDAI_ADDRESS) {
            revert InvalidParameter();
        }
        bytes memory otokenStakedUSDaiCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            STAKED_USDAI_SALT,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(
                    address(stakedUSDaiOtokenImpl),
                    deployer,
                    abi.encodeWithSelector(OToken.initialize.selector, "Staked USDai", "sUSDai", multisig)
                )
            )
        );

        // Prepare Create3 Calldata for USDai OAdapter
        if (
            CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, OADAPTER_USDAI_SALT)))
                != OADAPTER_USDAI_ADDRESS
        ) revert InvalidParameter();
        bytes memory oadapterUSDaiCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            OADAPTER_USDAI_SALT,
            abi.encodePacked(type(OAdapter).creationCode, abi.encode(USDAI_ADDRESS, lzEndpoint, msg.sender))
        );

        // Prepare Create3 Calldata for Staked USDai OAdapter
        if (
            CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, OADAPTER_STAKED_USDAI_SALT)))
                != OADAPTER_STAKED_USDAI_ADDRESS
        ) revert InvalidParameter();
        bytes memory oadapterStakedUSDaiCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            OADAPTER_STAKED_USDAI_SALT,
            abi.encodePacked(type(OAdapter).creationCode, abi.encode(STAKED_USDAI_ADDRESS, lzEndpoint, msg.sender))
        );

        // Print calldata
        console.log("from deployer multisig");
        console.log("target", address(CREATEX));
        console.log("OToken USDai calldata");
        console.logBytes(otokenUSDaiCalldata);
        console.log("OToken Staked USDai calldata");
        console.logBytes(otokenStakedUSDaiCalldata);
        console.log("OAdapter USDai calldata");
        console.logBytes(oadapterUSDaiCalldata);
        console.log("OAdapter Staked USDai calldata");
        console.logBytes(oadapterStakedUSDaiCalldata);

        // Log deployment
        _deployment.oTokenUSDai = USDAI_ADDRESS;
        _deployment.oTokenStakedUSDai = STAKED_USDAI_ADDRESS;
        _deployment.oAdapterUSDai = OADAPTER_USDAI_ADDRESS;
        _deployment.oAdapterStakedUSDai = OADAPTER_STAKED_USDAI_ADDRESS;
    }
}
