#!/usr/bin/env python3
"""Check the actual mounted installer, including Finder metadata."""
import pathlib
import plistlib
import subprocess
import sys
import tempfile
from ds_store import DSStore

image = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "dist/Lightkeeper.dmg").resolve()
failures = []
def require(condition, message):
    print(("PASS " if condition else "FAIL ") + message)
    if not condition:
        failures.append(message)

with tempfile.TemporaryDirectory(prefix="dmg-check-", dir=".build") as directory:
    mount = pathlib.Path(directory).resolve()
    subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(image)], check=True, stdout=subprocess.DEVNULL)
    try:
        app = mount / "Lightkeeper.app"
        require(app.is_dir() and (mount / "Applications").is_symlink()
                and (mount / "Applications").readlink() == pathlib.Path("/Applications"), "app and Applications install target exist")
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        icon = app / "Contents/Resources" / (info["CFBundleIconFile"] + ".icns")
        require(icon.exists() and icon.stat().st_size > 0, "app has its bundled icon")
        volume_icon = mount / ".VolumeIcon.icns"
        require(volume_icon.exists() and volume_icon.read_bytes() == icon.read_bytes(), "volume uses the lighthouse icon")
        flags = subprocess.run(["xattr", "-px", "com.apple.FinderInfo", str(mount)], capture_output=True, text=True)
        finder_info = bytes.fromhex(flags.stdout) if flags.returncode == 0 else b""
        require(len(finder_info) == 32 and int.from_bytes(finder_info[8:10], "big") & 0x0400 != 0, "mounted volume advertises its custom icon")
        require((mount / ".DS_Store").exists(), "installer layout is embedded")
        if (mount / ".DS_Store").exists():
            with DSStore.open(str(mount / ".DS_Store"), "r") as store:
                window = store["."]["bwsp"]
                view = store["."]["icvp"]
                positions = [store[name]["Iloc"] for name in ["Lightkeeper.app", "Applications"]]
                require(not window["ShowToolbar"] and not window["ShowSidebar"], "installer opens without Finder clutter")
                require(view["backgroundType"] == 2 and any(mount.glob(".background.*")), "branded installer background is included")
                require(positions[0][0] < positions[1][0] and positions[0][1] == positions[1][1]
                        and positions[1][0] - positions[0][0] > view["iconSize"], "app and destination are separated for dragging")
        require({item.name for item in mount.iterdir() if not item.name.startswith(".")} == {"Lightkeeper.app", "Applications"}, "only the app and install destination are visible")
        require((app / "Contents/Resources/LICENSE.txt").exists(), "license remains inside the app")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
if failures:
    sys.exit(1)
