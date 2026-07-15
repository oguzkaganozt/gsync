#!/bin/bash
# cloudfs installer: dependencies, files, config, and user services.
# Works from a clone or standalone:
#   curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/cloudfs/master/install.sh | bash
set -euo pipefail

RAW="https://raw.githubusercontent.com/oguzkaganozt/cloudfs/master"
CONF_DIR="$HOME/.config/cloudfs"
CONF="$CONF_DIR/folders.conf"
SERVERS_CONF="$CONF_DIR/servers.conf"
ENV_FILE="$CONF_DIR/environment"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo "")"
LOCAL_MODE=0
[[ -n "$DIR" && -f "$DIR/bin/cloudfs" ]] && LOCAL_MODE=1

mkdir -p "$CONF_DIR"
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<EOF
CLOUDFS_REMOTE=gdrive
CLOUDFS_ROOT=cloudfs/$(hostname)
CLOUDFS_DRIVE_MOUNT=$HOME/GoogleDrive
CLOUDFS_QUIET_SECONDS=15
CLOUDFS_ARCHIVE_DAYS=30
EOF
fi
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
REMOTE="${CLOUDFS_REMOTE:-gdrive}"
DRIVE_MOUNT="${CLOUDFS_DRIVE_MOUNT:-$HOME/GoogleDrive}"
[[ "$DRIVE_MOUNT" != /* ]] || DRIVE_MOUNT="$(realpath -m "$DRIVE_MOUNT")"

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

add_bookmark() {
  local path="$1" label="$2" bm="$HOME/.config/gtk-3.0/bookmarks"
  mkdir -p "$(dirname "$bm")"; touch "$bm"
  grep -Fq "file://$path " "$bm" || printf 'file://%s %s\n' "$path" "$label" >> "$bm"
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
command -v ssh >/dev/null || APT_PKGS+=(openssh-client)
if command -v nautilus >/dev/null && ! dpkg -s python3-nautilus >/dev/null 2>&1; then
  APT_PKGS+=(python3-nautilus)
fi
if [[ ${#APT_PKGS[@]} -gt 0 ]]; then
  echo "Installing packages: ${APT_PKGS[*]} (sudo required)"
  sudo apt-get install -y "${APT_PKGS[@]}"
fi

echo "==> Checking rclone remote '$REMOTE'"
if ! rclone listremotes | grep -Fxq "$REMOTE:"; then
  echo "No '$REMOTE' remote found. Starting rclone auth (a browser window will open)..."
  # Full 'drive' scope so the ~/GoogleDrive mount can browse your whole Drive.
  rclone config create "$REMOTE" drive scope=drive
else
  REMOTE_CONFIG="$(rclone config show "$REMOTE")"
  if ! grep -Eq '^type[[:space:]]*=[[:space:]]*drive$' <<< "$REMOTE_CONFIG"; then
    echo "ERROR: rclone remote '$REMOTE' exists but is not a Google Drive remote." >&2
    exit 1
  fi
  REMOTE_SCOPE="$(sed -n 's/^scope[[:space:]]*=[[:space:]]*//p' <<< "$REMOTE_CONFIG")"
  if [[ -n "$REMOTE_SCOPE" && "$REMOTE_SCOPE" != "drive" ]]; then
    echo "ERROR: rclone remote '$REMOTE' uses scope '$REMOTE_SCOPE'; full 'drive' scope is required." >&2
    exit 1
  fi
fi

echo "==> Installing files ($([[ $LOCAL_MODE -eq 1 ]] && echo 'from local repo' || echo 'from GitHub'))"
fetch "bin/cloudfs"                       "$HOME/.local/bin/cloudfs"                             755
fetch "bin/cloudfs-tray"                  "$HOME/.local/bin/cloudfs-tray"                        755
fetch "systemd/cloudfs.service"           "$HOME/.config/systemd/user/cloudfs.service"           644
fetch "systemd/cloudfs-tray.service"      "$HOME/.config/systemd/user/cloudfs-tray.service"      644
fetch "systemd/cloudfs-mount@.service"    "$HOME/.config/systemd/user/cloudfs-mount@.service"    644

# File-manager right-click integration
if command -v nautilus >/dev/null; then
  # Top-level context menu via nautilus-python extension
  fetch "share/filemanager/cloudfs_extension.py" \
        "$HOME/.local/share/nautilus-python/extensions/cloudfs_extension.py" 644
  nautilus -q 2>/dev/null || true   # reload extensions (closes open file windows)
  echo "    Nautilus: right-click a folder -> 'Sync to Google Drive'"
fi
if command -v nemo >/dev/null || [[ -d "$HOME/.local/share/nemo" ]]; then
  fetch "share/filemanager/sync-to-google-drive" \
        "$HOME/.local/share/nemo/scripts/Sync to Google Drive" 755
  echo "    Nemo: right-click a folder -> Scripts -> 'Sync to Google Drive'"
fi

if [[ ! -f "$CONF" ]]; then
  echo "==> Creating default config: $CONF"
    cat > "$CONF" <<'EOF'
# cloudfs watched folders
# Format:  LOCAL_FOLDER|DRIVE_TARGET_FOLDER|MODE(oneway|twoway)
# Prefer the CLI:  cloudfs add <dir> [drive_path] [--two-way]
EOF
else
  echo "==> Keeping existing config: $CONF"
fi

if [[ ! -f "$SERVERS_CONF" ]]; then
  cat > "$SERVERS_CONF" <<'EOF'
# SSH Host aliases registered with: cloudfs server add <alias>
EOF
fi

"$HOME/.local/bin/cloudfs" _validate

echo "==> Enabling services"
systemctl --user daemon-reload
if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
  systemctl --user set-environment "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" || true
fi
systemctl --user enable --now cloudfs
systemctl --user try-restart cloudfs 2>/dev/null || true
systemctl --user enable --now cloudfs-mount@gdrive
systemctl --user try-restart cloudfs-mount@gdrive 2>/dev/null || true

add_bookmark "$DRIVE_MOUNT" "Google Drive"
echo "    Files sidebar: 'Google Drive' bookmark added"

while IFS= read -r alias; do
  [[ -n "$alias" && "$alias" != \#* ]] || continue
  if [[ ! "$alias" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || "$alias" == "gdrive" || "$alias" == "GoogleDrive" ]]; then
    echo "WARNING: skipping invalid server alias in servers.conf: $alias" >&2
    continue
  fi
  mountpoint="$HOME/$alias"
  if systemctl --user is-active -q "cloudfs-mount@$alias"; then
    add_bookmark "$mountpoint" "$alias"
    systemctl --user enable "cloudfs-mount@$alias" || true
    systemctl --user try-restart "cloudfs-mount@$alias" || true
    continue
  fi
  if [[ -L "$mountpoint" || ( -d "$mountpoint" && -n "$(ls -A "$mountpoint" 2>/dev/null)" ) ]]; then
    echo "WARNING: not mounting '$alias' over non-empty path: $mountpoint" >&2
    continue
  fi
  mkdir -p "$mountpoint"
  add_bookmark "$mountpoint" "$alias"
  if ! systemctl --user enable --now "cloudfs-mount@$alias"; then
    echo "WARNING: '$alias' remains registered but could not be mounted." >&2
  fi
done < "$SERVERS_CONF"

if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  systemctl --user enable --now cloudfs-tray
  systemctl --user try-restart cloudfs-tray 2>/dev/null || true
else
  systemctl --user enable cloudfs-tray || true
  echo "(no display detected; tray will start with your next graphical session)"
fi

echo
echo "Done. cloudfs is running in the background; look for the cloud icon in your tray."
echo "  cloudfs add <dir>          # sync a folder to Drive"
echo "  cloudfs server add <host>  # mount an SSH Host alias"
echo "  cloudfs status             # sync and mount state"
echo "  cloudfs log                # live sync log"
