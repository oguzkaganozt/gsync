#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
FAKE_BIN="$TMP/bin"
LOG="$TMP/commands.log"
mkdir -p "$HOME" "$FAKE_BIN"
touch "$LOG"
export TEST_COMMAND_LOG="$LOG"
export PATH="$FAKE_BIN:/usr/bin:/bin"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "'$2' not found in $1"; }

cat > "$FAKE_BIN/rclone" <<'EOF'
#!/bin/bash
case "${1:-}" in
  version) echo "rclone v1.74.3" ;;
  listremotes) echo "gdrive:" ;;
  config)
    echo "type = ${TEST_RCLONE_TYPE:-drive}"
    [[ -z "${TEST_RCLONE_SCOPE:-}" ]] || echo "scope = $TEST_RCLONE_SCOPE"
    ;;
  *) exit 0 ;;
esac
EOF

cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl' >> "$TEST_COMMAND_LOG"
printf ' %s' "$@" >> "$TEST_COMMAND_LOG"
printf '\n' >> "$TEST_COMMAND_LOG"
[[ "${2:-}" == "is-active" ]] && exit 1
exit 0
EOF

for command in inotifywait python3 notify-send fusermount ssh nautilus dpkg; do
  cat > "$FAKE_BIN/$command" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$FAKE_BIN/$command"
done
chmod +x "$FAKE_BIN/rclone" "$FAKE_BIN/systemctl"

bash "$ROOT/install.sh" >/dev/null

assert_file "$HOME/.local/bin/cloudfs"
assert_file "$HOME/.local/bin/cloudfs-tray"
assert_file "$HOME/.config/systemd/user/cloudfs.service"
assert_file "$HOME/.config/systemd/user/cloudfs-mount@.service"
assert_file "$HOME/.config/cloudfs/environment"
assert_file "$HOME/.config/cloudfs/folders.conf"
assert_file "$HOME/.config/cloudfs/servers.conf"
assert_contains "$HOME/.config/gtk-3.0/bookmarks" "file://$HOME/GoogleDrive Google Drive"
assert_contains "$LOG" "systemctl --user enable --now cloudfs-mount@gdrive"

if TEST_RCLONE_TYPE=sftp bash "$ROOT/install.sh" >/dev/null 2>&1; then
  fail "installer accepted a non-Drive rclone remote"
fi
if TEST_RCLONE_SCOPE=drive.file bash "$ROOT/install.sh" >/dev/null 2>&1; then
  fail "installer accepted a restricted Google Drive scope"
fi

printf 'vps\n' >> "$HOME/.config/cloudfs/servers.conf"
printf '%s|safe/vps|oneway\n' "$HOME/vps" > "$HOME/.config/cloudfs/folders.conf"
if bash "$ROOT/install.sh" >/dev/null 2>&1; then
  fail "installer accepted a server mount overlapping a sync root"
fi
: > "$HOME/.config/cloudfs/folders.conf"
bash "$ROOT/install.sh" >/dev/null
assert_contains "$HOME/.config/gtk-3.0/bookmarks" "file://$HOME/vps vps"
assert_contains "$LOG" "systemctl --user enable --now cloudfs-mount@vps"

bash "$ROOT/uninstall.sh" >/dev/null
[[ ! -e "$HOME/.local/bin/cloudfs" ]] || fail "cloudfs binary was not removed"
[[ -f "$HOME/.config/cloudfs/servers.conf" ]] || fail "server config should be preserved"
if grep -Fq "file://$HOME/vps " "$HOME/.config/gtk-3.0/bookmarks"; then
  fail "server bookmark was not removed"
fi

echo "Install tests passed."
