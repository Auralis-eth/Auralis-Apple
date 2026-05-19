#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

key="$(printf '%s' "${AURALIS_ALCHEMY_API_KEY:-}" | tr -d '[:space:]')"

if [ -z "$key" ]; then
  echo "error: AURALIS_ALCHEMY_API_KEY must be set for Release builds." >&2
  exit 1
fi

if printf '%s' "$key" | /usr/bin/grep -Eiq \
  'placeholder|replace|changeme|todo|example|your[-_]?alchemy|your[-_]?api|your_|YOUR_|^\$\(.*\)$|^<#[^>]+#>$|^api_key$'; then
  echo "error: AURALIS_ALCHEMY_API_KEY contains a placeholder value for Release builds." >&2
  exit 1
fi
