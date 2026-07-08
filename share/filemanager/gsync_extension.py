"""Nautilus extension: top-level right-click menu items for gsync.

Installed to ~/.local/share/nautilus-python/extensions/ (needs python3-nautilus).
Shows "Add to gsync" on unwatched folders and "Remove from gsync" on watched
ones. Right-clicking a file targets the file's parent folder.
"""
import os
import subprocess

import gi

try:
    gi.require_version("Nautilus", "4.0")
except ValueError:
    gi.require_version("Nautilus", "3.0")
from gi.repository import Nautilus, GObject  # noqa: E402

GSYNC = os.path.expanduser("~/.local/bin/gsync")
CONF = os.path.expanduser("~/.config/gsync/folders.conf")
MOUNT = os.path.expanduser(os.environ.get("GSYNC_MOUNT", "~/GoogleDrive"))


def _watched_dirs():
    dirs = set()
    try:
        with open(CONF) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                p = line.split("|", 1)[0]
                dirs.add(os.path.expanduser(p))
    except OSError:
        pass
    return dirs


def _notify(msg):
    try:
        subprocess.Popen(
            ["notify-send", "--app-name=gsync", "gsync", msg],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


def _path_of(file_info):
    loc = file_info.get_location()
    return loc.get_path() if loc else None


def _target_dir(file_info):
    p = _path_of(file_info)
    if p is None:
        return None
    p = p if os.path.isdir(p) else os.path.dirname(p)
    # Paths on the Drive mount are already on Drive — offer no menu there.
    if p == MOUNT or p.startswith(MOUNT + os.sep):
        return None
    return p


class GsyncMenuProvider(GObject.GObject, Nautilus.MenuProvider):
    def _run(self, verb, paths):
        msgs = []
        for p in paths:
            r = subprocess.run([GSYNC, verb, p], capture_output=True, text=True)
            msgs.append((r.stdout or r.stderr or "done").strip())
        _notify("\n".join(msgs))

    def _make_items(self, paths):
        watched = _watched_dirs()
        add_paths = sorted(p for p in paths if p not in watched)
        rm_paths = sorted(p for p in paths if p in watched)
        items = []
        if add_paths:
            it = Nautilus.MenuItem(
                name="GsyncMenuProvider::add",
                label="Sync to Google Drive",
                tip="Keep this folder continuously synced to Google Drive",
            )
            it.connect("activate", lambda _i: self._run("add", add_paths))
            items.append(it)
        if rm_paths:
            it = Nautilus.MenuItem(
                name="GsyncMenuProvider::remove",
                label="Stop syncing this folder",
                tip="Stop syncing (files already on Drive are kept)",
            )
            it.connect("activate", lambda _i: self._run("remove", rm_paths))
            items.append(it)
        return items

    # Nautilus 4.0: (files) / 3.0: (window, files) — take the last arg.
    def get_file_items(self, *args):
        files = args[-1]
        paths = {d for d in (_target_dir(f) for f in files) if d}
        if not paths:
            return []
        return self._make_items(paths)

    # Right-click on empty space inside an open folder.
    def get_background_items(self, *args):
        folder = args[-1]
        p = _path_of(folder)
        if not p or not os.path.isdir(p):
            return []
        return self._make_items({p})
