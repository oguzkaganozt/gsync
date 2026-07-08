# gsync

Set-and-forget folder sync to Google Drive for Linux — with a system tray icon.

Pick folders; gsync watches them with **inotify** and syncs to Google Drive
with **rclone** the moment something changes (15s quiet window merges rapid
saves into one pass). A cloud icon in your tray shows what's happening:

| Icon | Meaning |
|---|---|
| grey cloud | idle, watching |
| bright cloud + arrow | syncing right now |
| amber cloud + `!` | last sync had errors |
| slashed cloud | paused |

Left-click the icon to sync now; right-click for the menu (sync now,
add folder via a folder picker, pause/resume, view log, watched-folder list).
Everything starts automatically at login and recovers on failure
(systemd user services).

Two modes, per folder:

- **oneway** (default) — mirrors local → Drive. Backup semantics: your disk
  is the source of truth. No conflicts, ever.
- **twoway** — `rclone bisync`; Drive-side changes flow back too (picked up
  every ~5 min). Concurrent edits on both sides become conflict copies, not
  overwrites.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/gsync/master/install.sh | bash
```

The installer checks deps (`rclone` required; installs `inotify-tools` and
tray libs via apt if missing), creates the `gdrive` rclone remote if you
don't have one (browser OAuth, narrow `drive.file` scope), installs the
daemon + tray as systemd user services, and migrates config from the old
`gdrive-autosync` name if found.

## CLI

```bash
gsync add ~/Documents                     # watch (oneway, -> pc-backup/Documents)
gsync add ~/notes shared/notes --two-way  # custom Drive path, bidirectional
gsync list                                # what's being watched
gsync remove ~/Documents                  # stop watching (Drive files kept)
gsync sync                                # force a pass right now
gsync pause / gsync resume                # stop / start watching
gsync status                              # service + last sync state
gsync log                                 # follow live log
./uninstall.sh                            # remove (keeps config + remote)
```

Config lives at `~/.config/gsync/folders.conf`
(format: `LOCAL|DRIVE_PATH|MODE`); editing it by hand works too.

Default excludes: `node_modules`, `.cache`, `__pycache__`, `.venv`,
`target`, `build`, `*.tmp`, `*.swp`.

Environment overrides: `GSYNC_REMOTE` (default `gdrive`),
`GSYNC_QUIET_SECONDS` (default `15`).
