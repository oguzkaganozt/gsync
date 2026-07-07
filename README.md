# gdrive-autosync

Event-driven folder sync to Google Drive for Linux, with a small CLI.

Watches your folders with **inotify**; whenever something changes, it syncs
that folder to Google Drive with **rclone** (after a 15s quiet window, so
rapid saves become one sync). A safety pass runs periodically even without
events. Runs as a systemd **user** service — starts on login, restarts on
failure, logs to the journal.

Two modes, per folder:

- **oneway** (default) — mirrors local → Drive. Backup semantics: your disk
  is the source of truth, Drive is the copy. No conflicts, ever.
- **twoway** — `rclone bisync`; changes made on the Drive side flow back too
  (picked up by the periodic pass, every ~5 min when any twoway folder is
  configured). If both sides changed the same file between passes, rclone
  keeps both versions as conflict copies instead of overwriting.

## Install

One-liner (no clone needed):

```bash
curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/gdrive-autosync/master/install.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/oguzkaganozt/gdrive-autosync
cd gdrive-autosync && ./install.sh
```

The installer:

1. Verifies `rclone`, installs `inotify-tools` if missing (apt).
2. Creates the `gdrive` rclone remote if you don't have one
   (opens a browser for Google OAuth; uses the narrow `drive.file` scope —
   the token can only touch files the tool itself created).
3. Installs the watcher to `~/.local/bin`, the unit to
   `~/.config/systemd/user`, and enables the service.

## Use

```bash
gdrive-autosync add ~/Documents                    # watch (oneway, -> pc-backup/Documents)
gdrive-autosync add ~/notes shared/notes --two-way # custom Drive path, bidirectional
gdrive-autosync list                               # what's being watched
gdrive-autosync remove ~/Documents                 # stop watching (Drive files kept)
gdrive-autosync sync                               # force a pass right now
gdrive-autosync status                             # service state + folder list
gdrive-autosync log                                # follow live log
```

`add`/`remove` edit `~/.config/gdrive-autosync/folders.conf`
(format: `LOCAL|DRIVE_PATH|MODE`) and restart the service for you —
editing the file by hand works too.

Default excludes: `node_modules`, `.cache`, `__pycache__`, `.venv`,
`target`, `build`, `*.tmp`, `*.swp`.

Environment overrides (set in the unit if needed): `GDRIVE_REMOTE`
(default `gdrive`), `GDRIVE_QUIET_SECONDS` (default `15`).

## Operate

```bash
systemctl --user status gdrive-autosync    # state
journalctl --user -u gdrive-autosync -f    # live log
./uninstall.sh                             # remove (keeps config + remote)
```
