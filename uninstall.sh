#!/bin/bash
# cloudfs uninstaller. Keeps config, state, SSH config, rclone remotes, and
# all remote files.
set -u

SERVERS_CONF="$HOME/.config/cloudfs/servers.conf"
BM="$HOME/.config/gtk-3.0/bookmarks"
ENV_FILE="$HOME/.config/cloudfs/environment"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi
DRIVE_MOUNT="${CLOUDFS_DRIVE_MOUNT:-$HOME/GoogleDrive}"
[[ "$DRIVE_MOUNT" != /* ]] || DRIVE_MOUNT="$(realpath -m "$DRIVE_MOUNT")"

unmount_path() {
  fusermount -u "$1" 2>/dev/null || fusermount3 -u "$1" 2>/dev/null \
    || fusermount -uz "$1" 2>/dev/null || fusermount3 -uz "$1" 2>/dev/null || true
}

remove_bookmark() {
  local path="$1" tmp line
  [[ -f "$BM" ]] || return 0
  tmp="$(mktemp)"
  while IFS= read -r line; do
    [[ "$line" == "file://$path" || "$line" == "file://$path "* ]] || printf '%s\n' "$line"
  done < "$BM" > "$tmp"
  mv "$tmp" "$BM"
}

echo "==> Stopping services"
systemctl --user disable --now cloudfs-tray 2>/dev/null
systemctl --user disable --now cloudfs 2>/dev/null
systemctl --user disable --now cloudfs-mount@gdrive 2>/dev/null
unmount_path "$DRIVE_MOUNT"

if [[ -f "$SERVERS_CONF" ]]; then
  while IFS= read -r alias; do
    [[ -n "$alias" && "$alias" != \#* ]] || continue
    systemctl --user disable --now "cloudfs-mount@$alias" 2>/dev/null || true
    unmount_path "$HOME/$alias"
    remove_bookmark "$HOME/$alias"
    rmdir "$HOME/$alias" 2>/dev/null || true
  done < "$SERVERS_CONF"
fi

echo "==> Removing files"
rm -f "$HOME/.config/systemd/user/cloudfs.service" \
      "$HOME/.config/systemd/user/cloudfs-tray.service" \
      "$HOME/.config/systemd/user/cloudfs-mount@.service"
systemctl --user daemon-reload
rm -f "$HOME/.local/bin/cloudfs" "$HOME/.local/bin/cloudfs-tray"

rm -f "$HOME/.local/share/nautilus-python/extensions/cloudfs_extension.py" \
      "$HOME/.local/share/nemo/scripts/Sync to Google Drive"
command -v nautilus >/dev/null && nautilus -q 2>/dev/null

remove_bookmark "$DRIVE_MOUNT"

# Mountpoint (only if empty)
rmdir "$DRIVE_MOUNT" 2>/dev/null

echo
echo "cloudfs removed."
echo "Kept: ~/.config/cloudfs, ~/.local/state/cloudfs, ~/.ssh, and rclone remotes."
echo "Files on Google Drive and SSH servers are untouched."
