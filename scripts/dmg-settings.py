# dmgbuild settings for the drag-to-install disk image. Used by scripts/package.sh.
# Icon positions must match the arrow drawn by scripts/dmg-background.swift.
import os.path

application = defines["app"]  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
hide_extension = [appname]

background = defines["background"]  # noqa: F821
icon = defines["icon"]  # noqa: F821 (volume icon)
window_rect = ((200, 200), (600, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 128
text_size = 13
icon_locations = {appname: (150, 140), "Applications": (450, 140)}
