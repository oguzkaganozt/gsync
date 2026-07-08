#!/bin/bash
# gsync uninstaller. Keeps your config (~/.config/gsync) and the rclone remote.
set -u

systemctl --user disable --now gsync-tray 2>/dev/null
systemctl --user disable --now gsync 2>/dev/null
rm -f "$HOME/.config/systemd/user/gsync.service" \
      "$HOME/.config/systemd/user/gsync-tray.service"
systemctl --user daemon-reload
rm -f "$HOME/.local/bin/gsync" "$HOME/.local/bin/gsync-tray"

echo "gsync removed."
echo "Kept: ~/.config/gsync (config), ~/.local/state/gsync (state), rclone 'gdrive' remote."
echo "Files on Google Drive are untouched."
