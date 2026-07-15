"""Nautilus extension: top-level Google Drive sync actions for cloudfs.

Installed to ~/.local/share/nautilus-python/extensions/ (needs python3-nautilus).
Right-clicking a file targets its parent. Remote mounts are excluded because
their files already live on Drive or an SSH server.
"""
import os
import subprocess

import gi

try:
    gi.require_version("Nautilus", "4.0")
except ValueError:
    gi.require_version("Nautilus", "3.0")
from gi.repository import Nautilus, GObject  # noqa: E402

CLOUDFS = os.path.expanduser("~/.local/bin/cloudfs")
CONF_DIR = os.path.expanduser("~/.config/cloudfs")
CONF = os.path.join(CONF_DIR, "folders.conf")
SERVERS_CONF = os.path.join(CONF_DIR, "servers.conf")


def _drive_mount():
    value = os.environ.get("CLOUDFS_DRIVE_MOUNT")
    if not value:
        try:
            with open(os.path.join(CONF_DIR, "environment")) as fh:
                for line in fh:
                    key, separator, setting = line.strip().partition("=")
                    if separator and key == "CLOUDFS_DRIVE_MOUNT":
                        value = setting.strip("\"'")
        except OSError:
            pass
    value = os.path.expandvars(value or "~/GoogleDrive")
    return os.path.realpath(os.path.expanduser(value))


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
            ["notify-send", "--app-name=cloudfs", "cloudfs", msg],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


def _path_of(file_info):
    loc = file_info.get_location()
    return loc.get_path() if loc else None


def _remote_mounts():
    mounts = [_drive_mount()]
    try:
        with open(SERVERS_CONF) as fh:
            for line in fh:
                alias = line.strip()
                if alias and not alias.startswith("#"):
                    mounts.append(os.path.realpath(
                        os.path.join(os.path.expanduser("~"), alias)
                    ))
    except OSError:
        pass
    return mounts


def _is_remote_path(path):
    return any(path == mount or path.startswith(mount + os.sep)
               for mount in _remote_mounts())


def _target_dir(file_info):
    p = _path_of(file_info)
    if p is None:
        return None
    p = p if os.path.isdir(p) else os.path.dirname(p)
    if _is_remote_path(p):
        return None
    return p


class CloudfsMenuProvider(GObject.GObject, Nautilus.MenuProvider):
    def _run(self, verb, paths):
        msgs = []
        for p in paths:
            r = subprocess.run([CLOUDFS, verb, p], capture_output=True, text=True)
            msgs.append((r.stdout or r.stderr or "done").strip())
        _notify("\n".join(msgs))

    def _make_items(self, paths):
        watched = _watched_dirs()
        add_paths = sorted(p for p in paths if p not in watched)
        rm_paths = sorted(p for p in paths if p in watched)
        items = []
        if add_paths:
            it = Nautilus.MenuItem(
                name="CloudfsMenuProvider::add",
                label="Sync to Google Drive",
                tip="Keep this folder continuously synced to Google Drive",
            )
            it.connect("activate", lambda _i: self._run("add", add_paths))
            items.append(it)
        if rm_paths:
            it = Nautilus.MenuItem(
                name="CloudfsMenuProvider::remove",
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
        p = _target_dir(folder)
        if not p or not os.path.isdir(p):
            return []
        return self._make_items({p})
