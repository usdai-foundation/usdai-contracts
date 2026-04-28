#!/usr/bin/env bash

set -e

declare -A SCRIPTS=(
    ["deploy-test-environment"]="script/DeployTestEnvironment.s.sol:DeployTestEnvironment"
    ["deploy-test-pyusd-price-feed"]="script/DeployTestPYUSDPriceFeed.s.sol:DeployTestPYUSDPriceFeed"
    ["deploy-swap-adapter"]="script/DeploySwapAdapter.s.sol:DeploySwapAdapter"
    ["deploy-price-oracle"]="script/DeployPriceOracle.s.sol:DeployPriceOracle"
    ["deploy-oadapter"]="script/DeployOAdapter.s.sol:DeployOAdapter"
    ["deploy-otoken"]="script/DeployOToken.s.sol:DeployOToken"
    ["deploy-base-yield-escrow"]="script/DeployBaseYieldEscrow.s.sol:DeployBaseYieldEscrow"
    ["deploy-ousdai-utility"]="script/DeployOUSDaiUtility.s.sol:DeployOUSDaiUtility"
    ["deploy-usdai-queued-depositor"]="script/DeployUSDaiQueuedDepositor.s.sol:DeployUSDaiQueuedDepositor"
    ["deploy-predeposit-vault"]="script/DeployPredepositVault.s.sol:DeployPredepositVault"
    ["upgrade-usdai"]="script/UpgradeUSDai.s.sol:UpgradeUSDai"
    ["upgrade-staked-usdai"]="script/UpgradeStakedUSDai.s.sol:UpgradeStakedUSDai"
    ["upgrade-otoken"]="script/UpgradeOToken.s.sol:UpgradeOToken"
    ["upgrade-base-yield-escrow"]="script/UpgradeBaseYieldEscrow.s.sol:UpgradeBaseYieldEscrow"
    ["upgrade-ousdai-utility"]="script/UpgradeOUSDaiUtility.s.sol:UpgradeOUSDaiUtility"
    ["upgrade-usdai-queued-depositor"]="script/UpgradeUSDaiQueuedDepositor.s.sol:UpgradeUSDaiQueuedDepositor"
    ["upgrade-predeposit-vault"]="script/UpgradePredepositVault.s.sol:UpgradePredepositVault"
    ["staked-usdai-service-redemptions"]="script/StakedUSDaiServiceRedemptions.s.sol:StakedUSDaiServiceRedemptions"
    ["swap-adapter-set-token-whitelist"]="script/SwapAdapterSetTokenWhitelist.s.sol:SwapAdapterSetTokenWhitelist"
    ["price-oracle-add-price-feeds"]="script/PriceOracleAddPriceFeeds.s.sol:PriceOracleAddPriceFeeds"
    ["base-yield-escrow-set-rate-tiers"]="script/BaseYieldEscrowSetRateTiers.s.sol:BaseYieldEscrowSetRateTiers"
    ["oadapter-set-rate-limits"]="script/OAdapterSetRateLimits.s.sol:OAdapterSetRateLimits"
    ["usdaiqueueddepositor-update-deposit-cap"]="script/USDaiQueuedDepositorUpdateDepositCap.s.sol:USDaiQueuedDepositorUpdateDepositCap"
    ["usdaiqueueddepositor-update-deposit-eid-whitelist"]="script/USDaiQueuedDepositorUpdateDepositEidWhitelist.s.sol:USDaiQueuedDepositorUpdateDepositEidWhitelist"
    ["predepositvault-update-deposit-cap"]="script/PredepositVaultUpdateDepositCap.s.sol:PredepositVaultUpdateDepositCap"
    ["grant-role"]="script/GrantRole.s.sol:GrantRole"
    ["transfer-ownership"]="script/TransferOwnership.s.sol:TransferOwnership"
    ["deploy-omnichain-environment"]="script/DeployOmnichainEnvironment.s.sol:DeployOmnichainEnvironment"
    ["create3-proxy-calldata"]="script/Create3ProxyCalldata.s.sol:Create3ProxyCalldata"
    ["show"]="script/Show.s.sol:Show"
)

usage() {
    echo "Usage: $0 <command> [arguments...]"
    echo ""
    echo "Commands:"
    echo "  deploy-test-environment <base token> <swap router> <sequencer uptime feed> <base token price feed> <loan router> <tokens> <price feeds>"
    echo ""
    echo "  deploy-test-pyusd-price-feed"
    echo "  deploy-swap-adapter <base token> <swap router> <tokens> <admin>"
    echo "  deploy-price-oracle <sequencer uptime feed> <base token price feed> <tokens> <price feeds> <admin>"
    echo "  deploy-oadapter <token> <lz endpoint>"
    echo "  deploy-otoken <oadapter> <name> <symbol>"
    echo "  deploy-base-yield-escrow <deployer> <base token> <multisig>"
    echo ""
    echo "  upgrade-usdai"
    echo "  upgrade-staked-usdai <loan router> <admin fee recipient> <base admin fee rate> <loan router admin fee rate>"
    echo "  upgrade-otoken <token>"
    echo "  upgrade-base-yield-escrow"
    echo "  upgrade-ousdai-utility <lz endpoint>"
    echo "  upgrade-usdai-queued-depositor"
    echo "  upgrade-predeposit-vault <deposit vault> <deposit token> <min amount>"
    echo ""
    echo "  staked-usdai-service-redemptions <shares>"
    echo "  swap-adapter-set-token-whitelist <tokens>"
    echo "  price-oracle-add-price-feeds <tokens> <price feeds>"
    echo "  base-yield-escrow-set-rate-tiers <rates> <thresholds>"
    echo "  oadapter-set-rate-limits <oadapter> <dst eids> <limit> <window>"
    echo "  usdaiqueueddepositor-update-deposit-cap <deposit cap> <reset counter>"
    echo "  usdaiqueueddepositor-update-deposit-eid-whitelist <src eid> <dst eid> <whitelisted>"
    echo "  predepositvault-update-deposit-cap <predeposit vault> <deposit cap> <reset counter>"
    echo "  grant-role <target> <role> <account>"
    echo "  transfer-ownership <proxy> <account>"
    echo ""
    echo "  deploy-omnichain-environment <deployer> <lz endpoint> <multisig>"
    echo "  deploy-ousdai-utility <deployer> <lz endpoint> <o adapters> <multisig>"
    echo "  deploy-usdai-queued-depositor <deployer> <multisig> <whitelisted tokens> <min amounts>"
    echo "  deploy-predeposit-vault <deployer> <deposit token> <min deposit amount> <name> <dst eid> <multisig>"
    echo "  create3-proxy-calldata <deployer> <salt> <implementation> <data>"
    echo ""
    echo "  show"
}

# Check argument count
if [ "$#" -lt 1 ]; then
    usage
    exit 0
fi

# Check for NETWORK env var
if [[ -z "$NETWORK" ]]; then
    echo -e "Error: NETWORK env var missing.\n"
    usage
    exit 1
fi

# Check for <NETWORK>_RPC_URL env var
RPC_URL_VAR=${NETWORK^^}_RPC_URL
RPC_URL=${!RPC_URL_VAR}
if [[ -z "$RPC_URL" ]]; then
    echo -e "Error: $RPC_URL env var missing.\n"
    usage
    exit 1
fi

# Look up script
SCRIPT=${SCRIPTS[$1]}
if [[ -z "$SCRIPT" ]]; then
    echo -e "Error: unknown command \"$1\"\n"
    usage
    exit 1
fi

# Look up script signature
SIGNATURE=$(forge inspect --no-cache --contracts script "$SCRIPT" mi --json | grep -o "run(.*)")

echo -e "Running on $NETWORK\n"

if [[ ! -z "$LEDGER_DERIVATION_PATH" ]]; then
    forge script --rpc-url "$RPC_URL" --ledger --hd-paths "$LEDGER_DERIVATION_PATH" --sender "$LEDGER_ADDRESS" --broadcast -vvvv "$SCRIPT" --sig "$SIGNATURE" "${@:2}"
elif [[ ! -z "$PRIVATE_KEY" ]]; then
    forge script --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --sender "$(cast wallet address "$PRIVATE_KEY")" --broadcast -vvvv "$SCRIPT" --sig "$SIGNATURE" "${@:2}"
else
    forge script --rpc-url "$RPC_URL" -vvvv "$SCRIPT" --sig "$SIGNATURE" "${@:2}"
fi
