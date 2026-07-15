#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
FAKE_BIN="$TMP/bin"
STATE="$TMP/systemd-active"
LOG="$TMP/commands.log"
mkdir -p "$HOME" "$FAKE_BIN"
touch "$STATE" "$LOG"
export PATH="$FAKE_BIN:/usr/bin:/bin"
export TEST_SYSTEMD_STATE="$STATE"
export TEST_COMMAND_LOG="$LOG"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "'$2' not found in $1"; }

cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/bin/bash
set -u
[[ "${1:-}" == "--user" ]] && shift
action="${1:-}"; shift 2>/dev/null || true
case "$action" in
  is-active)
    [[ "${1:-}" == "-q" ]] && shift
    grep -Fxq "${1:-}" "$TEST_SYSTEMD_STATE"
    ;;
  is-failed) exit 1 ;;
  show)
    unit="${1:-}"
    if grep -Fxq "$unit" "$TEST_SYSTEMD_STATE"; then
      printf 'Result=success\nActiveState=active\nSubState=running\n'
    else
      printf 'Result=success\nActiveState=inactive\nSubState=dead\n'
    fi
    ;;
  enable|start)
    [[ "${1:-}" == "--now" ]] && shift
    unit="${1:-}"
    grep -Fxq "$unit" "$TEST_SYSTEMD_STATE" || printf '%s\n' "$unit" >> "$TEST_SYSTEMD_STATE"
    printf 'systemctl %s %s\n' "$action" "$unit" >> "$TEST_COMMAND_LOG"
    ;;
  stop|disable)
    [[ "${1:-}" == "--now" ]] && shift
    unit="${1:-}"
    tmp="$(mktemp)"
    grep -Fxv "$unit" "$TEST_SYSTEMD_STATE" > "$tmp" || true
    mv "$tmp" "$TEST_SYSTEMD_STATE"
    printf 'systemctl %s %s\n' "$action" "$unit" >> "$TEST_COMMAND_LOG"
    ;;
  restart|daemon-reload|try-restart) exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$FAKE_BIN/ssh" <<'EOF'
#!/bin/bash
[[ "${1:-}" == "-G" ]] && exit 0
exit 0
EOF

cat > "$FAKE_BIN/rclone" <<'EOF'
#!/bin/bash
printf 'rclone' >> "$TEST_COMMAND_LOG"
printf ' %s' "$@" >> "$TEST_COMMAND_LOG"
printf '\n' >> "$TEST_COMMAND_LOG"
if [[ "${TEST_RCLONE_FAIL_SYNC:-0}" == "1" && "${1:-}" == "sync" ]]; then
  exit 1
fi
EOF

for command in xdg-open fusermount fusermount3; do
  cat > "$FAKE_BIN/$command" <<'EOF'
#!/bin/bash
printf '%s' "$(basename "$0")" >> "$TEST_COMMAND_LOG"
printf ' %s' "$@" >> "$TEST_COMMAND_LOG"
printf '\n' >> "$TEST_COMMAND_LOG"
EOF
  chmod +x "$FAKE_BIN/$command"
done
chmod +x "$FAKE_BIN/systemctl" "$FAKE_BIN/ssh" "$FAKE_BIN/rclone"

CLOUDFS="$ROOT/bin/cloudfs"

if "$CLOUDFS" server add '../bad' >/dev/null 2>&1; then
  fail "invalid alias was accepted"
fi

mkdir -p "$HOME/local"
for target in /cloudfs/test 'folder//test' 'folder/../test' 'folder|test'; do
  if "$CLOUDFS" add "$HOME/local" "$target" >/dev/null 2>&1; then
    fail "unsafe Drive target was accepted: $target"
  fi
done

"$CLOUDFS" add "$HOME/local" safe/test >/dev/null
if TEST_RCLONE_FAIL_SYNC=1 "$CLOUDFS" sync >/dev/null 2>&1; then
  fail "failed rclone sync returned success"
fi
"$CLOUDFS" remove "$HOME/local" >/dev/null

printf '%s|safe/test|invalid\n' "$HOME/local" > "$HOME/.config/cloudfs/folders.conf"
if "$CLOUDFS" list >/dev/null 2>&1; then
  fail "invalid persisted sync mode was accepted"
fi
printf '%s|safe/test|oneway\n%s|/safe/test|oneway\n' \
  "$HOME/local" "$HOME/other" > "$HOME/.config/cloudfs/folders.conf"
if "$CLOUDFS" list >/dev/null 2>&1; then
  fail "unsafe persisted Drive target was accepted"
fi
: > "$HOME/.config/cloudfs/folders.conf"

cat > "$HOME/.config/cloudfs/environment" <<EOF
CLOUDFS_DRIVE_MOUNT=$HOME/./vps
EOF
if "$CLOUDFS" server add vps >/dev/null 2>&1; then
  fail "server mount overlapping the Drive mount was accepted"
fi
rm "$HOME/.config/cloudfs/environment"

mkdir -p "$HOME/other"
"$CLOUDFS" add "$HOME/other" safe/other >/dev/null
if "$CLOUDFS" server add other >/dev/null 2>&1; then
  fail "server mount overlapping an existing sync root was accepted"
fi
"$CLOUDFS" remove "$HOME/other" >/dev/null

"$CLOUDFS" server add vps >/dev/null
[[ "$(<"$HOME/.config/cloudfs/servers.conf")" == "vps" ]] || fail "server was not registered"
assert_contains "$HOME/.config/gtk-3.0/bookmarks" "file://$HOME/vps vps"
assert_contains "$STATE" "cloudfs-mount@vps.service"

expected="vps|mounted|$HOME/vps"
[[ "$("$CLOUDFS" server list --plain)" == "$expected" ]] || fail "plain server list is incorrect"

"$CLOUDFS" _mount vps
assert_contains "$LOG" "rclone mount :sftp: $HOME/vps"
assert_contains "$LOG" "--sftp-ssh ssh -o BatchMode=yes vps"

if "$CLOUDFS" server add vps >/dev/null 2>&1; then
  fail "duplicate server was accepted"
fi

mkdir -p "$HOME/vps/project"
if "$CLOUDFS" add "$HOME/vps/project" >/dev/null 2>&1; then
  fail "a folder inside a server mount was accepted for Drive sync"
fi
rmdir "$HOME/vps/project"

"$CLOUDFS" server remove vps >/dev/null
[[ ! -s "$HOME/.config/cloudfs/servers.conf" ]] || fail "server registration was not removed"
if grep -Fq "file://$HOME/vps " "$HOME/.config/gtk-3.0/bookmarks"; then
  fail "server bookmark was not removed"
fi

mkdir -p "$HOME/GoogleDrive"
touch "$HOME/GoogleDrive/local-file"
if "$CLOUDFS" _mount gdrive >/dev/null 2>&1; then
  fail "Google Drive mounted over a non-empty directory"
fi
rm "$HOME/GoogleDrive/local-file"
"$CLOUDFS" _mount gdrive
assert_contains "$LOG" "rclone mount gdrive: $HOME/GoogleDrive"

echo "CLI tests passed."
