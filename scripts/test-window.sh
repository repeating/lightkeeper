#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/swift.sh build --product Lightkeeper
bin="$(scripts/swift.sh build --show-bin-path)"
architecture="$(uname -m)"
swiftc -swift-version 5 -target "$architecture-apple-macosx14.0" \
    -I "$bin/Modules" -I Sources/CSQLite -D BEACON_WINDOW_TEST \
    Sources/Lightkeeper/*.swift Tests/WindowTests/WindowSelfTest.swift \
    "$bin"/BeaconCore.build/*.swift.o -o .build/BeaconWindowTests
exec .build/BeaconWindowTests
