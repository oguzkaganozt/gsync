#!/bin/bash
# gsync installer: deps -> files -> config -> systemd services (daemon + tray).
# Works from a clone or standalone:
#   curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/gsync/master/install.sh | bash
set -euo pipefail

RAW="https://raw.githubusercontent.com/oguzkaganozt/gsync/master"
CONF_DIR="$HOME/.config/gsync"
CONF="$CONF_DIR/folders.conf"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo "")"
LOCAL_MODE=0
[[ -n "$DIR" && -f "$DIR/bin/gsync" ]] && LOCAL_MODE=1

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
  echo "rclone not found. Install the official build (recommended):"
  echo "  curl https://rclone.org/install.sh | sudo bash"
  exit 1
fi
# Old rclone builds (< 1.66) have a rough bisync; warn if twoway may be used.
RCLONE_VER=$(rclone version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ -n "$RCLONE_VER" ]] && awk "BEGIN{exit !($RCLONE_VER < 1.66)}"; then
  echo "NOTE: rclone $RCLONE_VER is old. For reliable --two-way folders, upgrade:"
  echo "  curl https://rclone.org/install.sh | sudo bash"
fi

APT_PKGS=()
command -v inotifywait >/dev/null || APT_PKGS+=(inotify-tools)
python3 -c "import gi, cairo" 2>/dev/null || APT_PKGS+=(python3-gi python3-gi-cairo)
python3 -c "import gi; gi.require_version('AyatanaAppIndicator3','0.1')" 2>/dev/null \
  || APT_PKGS+=(gir1.2-ayatanaappindicator3-0.1)
command -v notify-send >/dev/null || APT_PKGS+=(libnotify-bin)
command -v fusermount >/dev/null || command -v fusermount3 >/dev/null || APT_PKGS+=(fuse3)
if command -v nautilus >/dev/null && ! dpkg -s python3-nautilus >/dev/null 2>&1; then
  APT_PKGS+=(python3-nautilus)
fi
if [[ ${#APT_PKGS[@]} -gt 0 ]]; then
  echo "Installing packages: ${APT_PKGS[*]} (sudo required)"
  sudo apt-get install -y "${APT_PKGS[@]}"
fi

echo "==> Checking rclone remote 'gdrive'"
if ! rclone listremotes | grep -q '^gdrive:$'; then
  echo "No 'gdrive' remote found. Starting rclone auth (a browser window will open)..."
  # Full 'drive' scope so the ~/GoogleDrive mount can browse your whole Drive.
  rclone config create gdrive drive scope=drive
fi

echo "==> Installing files ($([[ $LOCAL_MODE -eq 1 ]] && echo 'from local repo' || echo 'from GitHub'))"
fetch "bin/gsync"                  "$HOME/.local/bin/gsync"                            755
fetch "bin/gsync-tray"             "$HOME/.local/bin/gsync-tray"                       755
fetch "systemd/gsync.service"       "$HOME/.config/systemd/user/gsync.service"          644
fetch "systemd/gsync-tray.service"  "$HOME/.config/systemd/user/gsync-tray.service"     644
fetch "systemd/gsync-mount.service" "$HOME/.config/systemd/user/gsync-mount.service"    644

# File-manager right-click integration
if command -v nautilus >/dev/null; then
  # Top-level context menu via nautilus-python extension
  fetch "share/filemanager/gsync_extension.py" \
        "$HOME/.local/share/nautilus-python/extensions/gsync_extension.py" 644
  rm -f "$HOME/.local/share/nautilus/scripts/Add to gsync"  # old Scripts variant
  nautilus -q 2>/dev/null || true   # reload extensions (closes open file windows)
  echo "    Nautilus: right-click a folder -> 'Sync to Google Drive'"
fi
if command -v nemo >/dev/null || [[ -d "$HOME/.local/share/nemo" ]]; then
  rm -f "$HOME/.local/share/nemo/scripts/Add to gsync"  # old name
  fetch "share/filemanager/sync-to-google-drive" \
        "$HOME/.local/share/nemo/scripts/Sync to Google Drive" 755
  echo "    Nemo: right-click a folder -> Scripts -> 'Sync to Google Drive'"
fi

# Migrate from the old gdrive-autosync name, if present
OLD_CONF="$HOME/.config/gdrive-autosync/folders.conf"
if [[ -f "$OLD_CONF" && ! -f "$CONF" ]]; then
  echo "==> Migrating config from gdrive-autosync"
  mkdir -p "$CONF_DIR"
  cp "$OLD_CONF" "$CONF"
  [[ -d "$HOME/.local/state/gdrive-autosync" ]] && \
    cp -rn "$HOME/.local/state/gdrive-autosync" "$HOME/.local/state/gsync" 2>/dev/null || true
fi
systemctl --user disable --now gdrive-autosync 2>/dev/null || true
rm -f "$HOME/.local/bin/gdrive-autosync" "$HOME/.config/systemd/user/gdrive-autosync.service"

if [[ ! -f "$CONF" ]]; then
  echo "==> Creating default config: $CONF"
  mkdir -p "$CONF_DIR"
  cat > "$CONF" <<'EOF'
# gsync watched folders
# Format:  LOCAL_FOLDER|DRIVE_TARGET_FOLDER|MODE(oneway|twoway)
# Prefer the CLI:  gsync add <dir> [drive_path] [--two-way]
EOF
else
  echo "==> Keeping existing config: $CONF"
fi

echo "==> Enabling services"
systemctl --user daemon-reload
systemctl --user enable --now gsync
systemctl --user try-restart gsync 2>/dev/null || true
systemctl --user enable --now gsync-mount
systemctl --user try-restart gsync-mount 2>/dev/null || true

# Nautilus sidebar bookmark for the Drive mount
BM="$HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$(dirname "$BM")"; touch "$BM"
if ! grep -q "file://$HOME/GoogleDrive" "$BM"; then
  echo "file://$HOME/GoogleDrive Google Drive" >> "$BM"
  echo "    Files sidebar: 'Google Drive' bookmark added"
fi
if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  systemctl --user enable --now gsync-tray
  systemctl --user try-restart gsync-tray 2>/dev/null || true
else
  systemctl --user enable gsync-tray || true
  echo "(no display detected; tray will start with your next graphical session)"
fi

echo
echo "Done. gsync is watching in the background; look for the cloud icon in your tray."
echo "  gsync add <dir>     # watch a folder"
echo "  gsync status        # state + folder list"
echo "  gsync log           # live log"
