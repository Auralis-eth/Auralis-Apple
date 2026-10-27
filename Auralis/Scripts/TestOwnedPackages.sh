#!/bin/bash

set -euo pipefail

# Keep this list aligned with the final package graph. The app test plans do not execute these
# suites, so CI must invoke this lane independently.
packages=(
    AccountsCore
    AuraPlayEngines
    AuraUI
    AuralisContext
    AuralisFoundation
    MissionControlFeature
    OperatorsFeature
    AuralisPolicy
    AuralisReceipts
    AuralisRuntime
    RuntimeKit
)

for package in "${packages[@]}"; do
    echo "Testing ${package}"
    swift test --disable-sandbox --package-path "${package}"
done

# This package intentionally owns reusable fixtures but no test target. Compiling it independently
# proves that its dependency-clean support API remains usable without manufacturing an empty suite.
echo "Building AuralisTestSupport"
swift build --disable-sandbox --package-path AuralisTestSupport
