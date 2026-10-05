#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# This Mac has older private manifest interfaces alongside a newer library.
# Use a project-local copy with public interfaces; never alter system tools.
api=/Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI
if [[ -f "$api/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface" ]]; then
    if [[ ! -d .build-tools/ManifestAPI ]]; then
        mkdir -p .build-tools
        cp -R "$api" .build-tools/ManifestAPI
        rm -f .build-tools/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build-tools"
fi
exec swift "$@"
