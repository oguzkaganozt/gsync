#!/bin/bash
# Removes gdrive-autosync (keeps your config and rclone remote).
set -euo pipefail

systemctl --user disable --now gdrive-autosync 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/gdrive-autosync.service"
systemctl --user daemon-reload
rm -f "$HOME/.local/bin/gdrive-autosync"

echo "Removed. Config kept at ~/.config/gdrive-autosync/ (delete manually if unwanted)."
echo "The rclone 'gdrive' remote was also kept (remove with: rclone config delete gdrive)."
