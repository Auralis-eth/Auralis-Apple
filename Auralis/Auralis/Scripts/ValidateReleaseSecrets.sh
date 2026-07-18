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
