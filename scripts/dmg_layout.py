#!/usr/bin/env python3
"""Create Finder's saved installer layout without Finder/AppleScript automation."""
import pathlib
import sys

import dmgbuild
from ds_store import DSStore

destination, app, readme, background = map(pathlib.Path, sys.argv[1:5])
mounted = {}

def remember_mount(path, options):
    mounted["path"] = pathlib.Path(path)

def save_view_style(event):
    if event.get("type") == "operation::finished" and event.get("operation") == "dsstore::create":
        with DSStore.open(str(mounted["path"] / ".DS_Store"), "r+") as store:
            store["."]["vstl"] = ("type", b"icnv")

dmgbuild.build_dmg(str(destination), "UP Sysdash", settings={
    "format": "UDZO",
    "compression_level": 9,
    "filesystem": "HFS+",
    "files": [str(app), (str(readme), ".ReadMe.txt")],
    "symlinks": {"Applications": "/Applications"},
    "icon": str(app / "Contents/Resources/AppIcon.icns"),
    "background": str(background),
    "window_rect": ((160, 100), (640, 480)),
    "default_view": "icon-view",
    "include_icon_view_settings": True,
    "include_list_view_settings": False,
    "arrange_by": None,
    "icon_locations": {
        "UP Sysdash.app": (170, 198),
        "Applications": (470, 198),
        ".ReadMe.txt": (1400, 200),
        ".background.png": (1100, 200),
        ".VolumeIcon.icns": (1250, 200),
    },
    "icon_size": 96,
    "text_size": 12,
    "label_pos": "bottom",
    "hide_extensions": [],
    "show_icon_preview": False,
    "show_item_info": False,
    "show_status_bar": False,
    "show_tab_view": False,
    "show_toolbar": False,
    "show_pathbar": False,
    "show_sidebar": False,
    "scroll_position": (0, 0),
    "create_hook": remember_mount,
}, callback=save_view_style, lookForHiDPI=False)
print(f"Unbound installer built: {destination}")
