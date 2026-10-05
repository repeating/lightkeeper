from pathlib import Path

project = Path.cwd()
format = "UDZO"
filesystem = "HFS+"
files = [str(project / "dist/Lightkeeper.app"), (defines["support"], ".support")]
symlinks = {"Applications": "/Applications"}
icon = str(project / "dist/Lightkeeper.app/Contents/Resources/Beacon.icns")
background = str(project / ".build/DMGBackground.png")
window_rect = ((200, 160), (680, 472))
default_view = "icon-view"
show_status_bar = show_tab_view = show_toolbar = show_pathbar = show_sidebar = False
arrange_by = None
grid_spacing = 80
icon_size = 112
text_size = 15
icon_locations = {"Lightkeeper.app": (175, 210), "Applications": (505, 210)}
