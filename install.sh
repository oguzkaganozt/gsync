#!/bin/bash
# gdrive-autosync installer: deps -> files -> config -> systemd user service.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$HOME/.config/gdrive-autosync"
CONF="$CONF_DIR/folders.conf"

echo "==> Checking dependencies"
if ! command -v rclone >/dev/null; then
  echo "rclone not found. Install it first:"
  echo "  sudo apt install rclone      # or: curl https://rclone.org/install.sh | sudo bash"
  exit 1
fi
if ! command -v inotifywait >/dev/null; then
  echo "inotify-tools not found; installing (sudo required)..."
  sudo apt-get install -y inotify-tools
fi

echo "==> Checking rclone remote 'gdrive'"
if ! rclone listremotes | grep -q '^gdrive:$'; then
  echo "No 'gdrive' remote found. Starting rclone auth (a browser window will open)..."
  rclone config create gdrive drive scope=drive.file
fi

echo "==> Installing files"
install -Dm755 "$DIR/bin/gdrive-autosync" "$HOME/.local/bin/gdrive-autosync"
install -Dm644 "$DIR/systemd/gdrive-autosync.service" \
  "$HOME/.config/systemd/user/gdrive-autosync.service"

if [[ ! -f "$CONF" ]]; then
  echo "==> Creating default config: $CONF"
  mkdir -p "$CONF_DIR"
  cat > "$CONF" <<'EOF'
# gdrive-autosync watched folders
# Format:  LOCAL_FOLDER|DRIVE_TARGET_FOLDER
# After editing: systemctl --user restart gdrive-autosync
#
# ~/Documents|pc-backup/documents
# ~/Pictures|pc-backup/pictures
EOF
  echo "    Edit it and add at least one folder line."
else
  echo "==> Keeping existing config: $CONF"
fi

echo "==> Enabling service"
systemctl --user daemon-reload
systemctl --user enable --now gdrive-autosync

echo
echo "Done. Useful commands:"
echo "  systemctl --user status gdrive-autosync     # service state"
echo "  journalctl --user -u gdrive-autosync -f     # live log"
echo "  $EDITOR $CONF                                # edit watched folders"
