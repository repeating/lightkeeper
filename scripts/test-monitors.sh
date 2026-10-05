#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/swift.sh build --product BeaconTests
bin="$(scripts/swift.sh build --show-bin-path)"
architecture="$(uname -m)"
swiftc -swift-version 5 -target "$architecture-apple-macosx14.0" \
    -I "$bin/Modules" -I Sources/CSQLite \
    Sources/Lightkeeper/CodexMonitor.swift Sources/Lightkeeper/ClaudeMonitor.swift \
    Tests/MonitorTests/Probe.swift "$bin"/BeaconCore.build/*.swift.o -o .build/BeaconMonitorTests
exec python3 Tests/MonitorTests/test_monitors.py .build/BeaconMonitorTests
