#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Separate build directories keep native test artifacts intact.
for architecture in arm64 x86_64; do
    scripts/swift.sh build -c release --product Lightkeeper \
        --triple "$architecture-apple-macosx14.0" --scratch-path ".build/distribution-$architecture"
done
app="$PWD/dist/Lightkeeper.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
# Remove the browser resources left by earlier generated bundles.
rm -rf "$app/Contents/Resources/BrowserExtension"
arm_bin="$(scripts/swift.sh build -c release --show-bin-path --triple arm64-apple-macosx14.0 --scratch-path .build/distribution-arm64)"
intel_bin="$(scripts/swift.sh build -c release --show-bin-path --triple x86_64-apple-macosx14.0 --scratch-path .build/distribution-x86_64)"
lipo -create "$arm_bin/Lightkeeper" "$intel_bin/Lightkeeper" -output "$app/Contents/MacOS/Lightkeeper"
if [[ ! -f "$app/Contents/Resources/Beacon.icns" || assets/SessionBeacon-icon.png -nt "$app/Contents/Resources/Beacon.icns" ]]; then
    mkdir -p .build/Beacon.iconset
    sips -z 1024 1024 assets/SessionBeacon-icon.png --out .build/Beacon.iconset/icon_512x512@2x.png >/dev/null
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" .build/Beacon.iconset/icon_512x512@2x.png --out ".build/Beacon.iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        if [[ "$size" != 512 ]]; then
            sips -z "$double" "$double" .build/Beacon.iconset/icon_512x512@2x.png --out ".build/Beacon.iconset/icon_${size}x${size}@2x.png" >/dev/null
        fi
    done
    iconutil -c icns .build/Beacon.iconset -o "$app/Contents/Resources/Beacon.icns"
fi
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Lightkeeper</string>
<key>CFBundleDisplayName</key><string>Lightkeeper</string>
<!-- Keep the original identifier so the rebrand retains preferences. -->
<key>CFBundleIdentifier</key><string>com.fadi.sessionbeacon</string>
<key>CFBundleExecutable</key><string>Lightkeeper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Beacon</string>
<key>CFBundleShortVersionString</key><string>1.3.2</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# A certificate-backed identity preserves authorization across updates.
# Without an installed identity, development builds remain ad-hoc signed.
codesign --force --sign "${BEACON_SIGNING_IDENTITY:--}" "$app"
printf '%s\n' "$app"
