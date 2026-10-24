#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

validate_key() {
  name="$1"
  value="$(printf '%s' "${2:-}" | tr -d '[:space:]')"
  missing_message="$3"
  placeholder_message="$4"

  if [ -z "$value" ]; then
    echo "error: $missing_message" >&2
    exit 1
  fi

  if printf '%s' "$value" | /usr/bin/grep -Eiq \
    'placeholder|replace|changeme|todo|example|your[-_]?alchemy|your[-_]?helius|your[-_]?api|your_|YOUR_|^\$\(.*\)$|^<#[^>]+#>$|^api_key$'; then
    echo "error: $placeholder_message" >&2
    exit 1
  fi
}

validate_key \
  "AURALIS_ALCHEMY_API_KEY" \
  "${AURALIS_ALCHEMY_API_KEY:-}" \
  "AURALIS_ALCHEMY_API_KEY must be set for Release builds." \
  "AURALIS_ALCHEMY_API_KEY contains a placeholder value for Release builds."

validate_key \
  "AURALIS_HELIUS_API_KEY" \
  "${AURALIS_HELIUS_API_KEY:-}" \
  "AURALIS_HELIUS_API_KEY must be set for Release builds." \
  "AURALIS_HELIUS_API_KEY contains a placeholder value for Release builds."

# The third secret in `Secrets.local.xcconfig.template`, and previously the one this gate did not
# check. An empty project ID does not crash — `AuralisWalletConnectionConfig.init` fails closed with
# "WalletConnect project ID is not configured" — so the failure mode was a Release that built,
# shipped, and simply had no WalletConnect, discovered by a person trying to connect a wallet rather
# than by the check that exists to catch exactly this.
validate_key \
  "AURALIS_WALLETCONNECT_PROJECT_ID" \
  "${AURALIS_WALLETCONNECT_PROJECT_ID:-}" \
  "AURALIS_WALLETCONNECT_PROJECT_ID must be set for Release builds." \
  "AURALIS_WALLETCONNECT_PROJECT_ID contains a placeholder value for Release builds."
