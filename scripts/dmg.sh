#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
# Packaging tools are isolated from the system Python and the app itself.
python="${BEACON_PYTHON:-python3}"
if [[ ! -x .build-tools/dmg/bin/python ]]; then
    "$python" -m venv .build-tools/dmg
fi
.build-tools/dmg/bin/python -m pip install --disable-pip-version-check --quiet -r scripts/dmg-requirements.txt
swift scripts/dmg-background.swift "$PWD/.build"
support="$(mktemp -d "$PWD/.build/dmg-support.XXXXXX")"
trap 'rm -rf "$support"' EXIT
cp docs/Install.txt "$support/Start Here.txt"
cp LICENSE "$support/LICENSE.txt"
cp assets/SessionBeacon-icon.png "$support/Lightkeeper Logo.png"
# dmgbuild sets the icon on the mounted volume and writes Finder layout metadata.
# It needs no Finder scripting or Automation permission.
.build-tools/dmg/bin/dmgbuild -s scripts/dmg-settings.py -D "support=$support" \
    Lightkeeper dist/Lightkeeper.dmg
hdiutil verify dist/Lightkeeper.dmg
.build-tools/dmg/bin/python scripts/test-dmg.py dist/Lightkeeper.dmg
(
    cd dist
    shasum -a 256 Lightkeeper.dmg > Lightkeeper.dmg.sha256
)
printf '%s\n' "$PWD/dist/Lightkeeper.dmg"
