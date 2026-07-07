#!/bin/bash
# gdrive-autosync installer: deps -> files -> config -> systemd user service.
# Works both from a cloned repo and standalone via:
#   curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/gdrive-autosync/master/install.sh | bash
set -euo pipefail

RAW="https://raw.githubusercontent.com/oguzkaganozt/gdrive-autosync/master"
CONF_DIR="$HOME/.config/gdrive-autosync"
CONF="$CONF_DIR/folders.conf"

# Detect local-repo mode (script sitting next to bin/ and systemd/)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo "")"
LOCAL_MODE=0
[[ -n "$DIR" && -f "$DIR/bin/gdrive-autosync" ]] && LOCAL_MODE=1

fetch() { # fetch <repo-relative-path> <dest> <mode>
  if [[ "$LOCAL_MODE" -eq 1 ]]; then
    install -Dm"$3" "$DIR/$1" "$2"
  else
    local tmp; tmp="$(mktemp)"
    curl -fsSL "$RAW/$1" -o "$tmp"
    install -Dm"$3" "$tmp" "$2"
    rm -f "$tmp"
  fi
}

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

echo "==> Installing files ($([[ $LOCAL_MODE -eq 1 ]] && echo 'from local repo' || echo 'from GitHub'))"
fetch "bin/gdrive-autosync" "$HOME/.local/bin/gdrive-autosync" 755
fetch "systemd/gdrive-autosync.service" "$HOME/.config/systemd/user/gdrive-autosync.service" 644

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
systemctl --user try-restart gdrive-autosync 2>/dev/null || true

echo
echo "Done. Useful commands:"
echo "  systemctl --user status gdrive-autosync     # service state"
echo "  journalctl --user -u gdrive-autosync -f     # live log"
echo "  \${EDITOR:-nano} $CONF                        # edit watched folders"
