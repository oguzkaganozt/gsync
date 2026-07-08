#!/bin/bash
# gsync uninstaller. Keeps your config (~/.config/gsync), state, and the
# rclone remote. Files on Google Drive are untouched.
set -u

echo "==> Stopping services"
systemctl --user disable --now gsync-tray 2>/dev/null
systemctl --user disable --now gsync 2>/dev/null
systemctl --user disable --now gsync-mount 2>/dev/null
fusermount -uz "$HOME/GoogleDrive" 2>/dev/null || fusermount3 -uz "$HOME/GoogleDrive" 2>/dev/null

echo "==> Removing files"
rm -f "$HOME/.config/systemd/user/gsync.service" \
      "$HOME/.config/systemd/user/gsync-tray.service" \
      "$HOME/.config/systemd/user/gsync-mount.service"
systemctl --user daemon-reload
rm -f "$HOME/.local/bin/gsync" "$HOME/.local/bin/gsync-tray"

# File-manager integration (current and legacy names)
rm -f "$HOME/.local/share/nautilus-python/extensions/gsync_extension.py" \
      "$HOME/.local/share/nautilus/scripts/Add to gsync" \
      "$HOME/.local/share/nemo/scripts/Sync to Google Drive" \
      "$HOME/.local/share/nemo/scripts/Add to gsync"
command -v nautilus >/dev/null && nautilus -q 2>/dev/null

# Sidebar bookmark
BM="$HOME/.config/gtk-3.0/bookmarks"
[[ -f "$BM" ]] && sed -i "\|file://$HOME/GoogleDrive|d" "$BM"

# Mountpoint (only if empty)
rmdir "$HOME/GoogleDrive" 2>/dev/null

echo
echo "gsync removed."
echo "Kept: ~/.config/gsync (config), ~/.local/state/gsync (state), rclone 'gdrive' remote."
echo "Files on Google Drive are untouched (including gsync/ and gsync/.archive)."
