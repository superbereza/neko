#!/usr/bin/env bash
# Compile and run the neko characterization tests with raw swiftc (no Xcode/SPM).
# Exit code reflects pass/fail.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(mktemp -d)/neko-tests"

swiftc -O \
    "$DIR/NekoCoreMirror.swift" \
    "$DIR/Tests.swift" \
    -o "$BIN"

"$BIN"
