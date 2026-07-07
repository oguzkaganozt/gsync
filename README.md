# gdrive-autosync

Event-driven, one-way folder backup to Google Drive for Linux.

Watches the folders you list in a config file with **inotify**; whenever
something changes, it mirrors that folder to Google Drive with **rclone**
(after a 15s quiet window, so rapid saves become one sync). A full safety
pass runs hourly even without events. Runs as a systemd **user** service —
starts on login, restarts on failure, logs to the journal.

One-way means: local disk is the source of truth, Drive is the backup.
No bidirectional conflict handling, by design.

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

## Configure

Edit `~/.config/gdrive-autosync/folders.conf`:

```
# LOCAL_FOLDER|DRIVE_TARGET_FOLDER
~/Documents|pc-backup/documents
~/projects/notes|pc-backup/notes
```

Then `systemctl --user restart gdrive-autosync`.

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
