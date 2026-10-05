#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
stage="$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto 'dist/Lightkeeper.app' "$stage/Lightkeeper.app"
ln -s /Applications "$stage/Applications"
cp docs/Install.txt "$stage/Start Here.txt"
cp LICENSE "$stage/LICENSE.txt"
cp assets/SessionBeacon-icon.png "$stage/Lightkeeper Logo.png"
cp 'dist/Lightkeeper.app/Contents/Resources/Beacon.icns' "$stage/.VolumeIcon.icns"
# Finder's custom-volume-icon flag, without changing system preferences.
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$stage"
hdiutil create -ov -volname 'Lightkeeper' -srcfolder "$stage" \
    -fs HFS+ -format UDZO 'dist/Lightkeeper.dmg'
hdiutil verify 'dist/Lightkeeper.dmg'
(
    cd dist
    shasum -a 256 Lightkeeper.dmg > Lightkeeper.dmg.sha256
)
printf '%s\n' "$PWD/dist/Lightkeeper.dmg"
