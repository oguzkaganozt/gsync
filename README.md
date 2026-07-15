# cloudfs

One Linux desktop tool for Google Drive sync and direct access to remote files.

cloudfs provides two deliberately separate capabilities:

1. **Google Drive** - browse the whole Drive at `~/GoogleDrive`, and keep
   selected local folders synced to Drive.
2. **SSH servers** - browse a registered server's home directory at
   `~/<ssh-alias>` without downloading a full offline copy.

Both kinds of remote storage appear in the Files (Nautilus) sidebar and are
managed from one tray icon. User-level systemd services start them at login
and recover from transient failures.

## How it works

- Google Drive access uses `rclone mount` and streams files on demand.
- Folder sync uses `rclone sync` or `rclone bisync`, triggered by `inotify`.
- Server access uses rclone's SFTP backend through the system OpenSSH client.
  Host, user, port, key, `ProxyJump`, and host-key rules come from
  `~/.ssh/config`.
- Mounts use isolated `cloudfs-mount@.service` instances, so one unavailable
  remote does not stop the others.

Server access is a live mount, not an offline mirror. If the server or network
is unavailable, its files are unavailable. Syncthing is a better fit when a
complete offline copy of a selected directory is required.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/cloudfs/master/install.sh | bash
```

The installer:

- checks for rclone and installs missing desktop/FUSE dependencies with apt;
- creates the `gdrive` rclone remote through browser OAuth when needed;
- installs the CLI, tray, systemd units, and file-manager integration;
- mounts Google Drive at `~/GoogleDrive`;
- adds Google Drive to the Files sidebar.

The Google Drive OAuth uses full Drive scope because browsing the whole Drive
requires access to files not created by cloudfs.

## Google Drive

Put cloud-only files directly under `~/GoogleDrive`. Files stream on demand;
edits are uploaded through rclone's write cache.

For local folders that must remain on disk and survive disk loss:

```bash
cloudfs add ~/Documents
cloudfs add ~/notes shared/notes --two-way
cloudfs list
cloudfs remove ~/Documents
cloudfs sync
cloudfs mount
cloudfs unmount
cloudfs open
```

The default one-way mode treats the local disk as the source of truth.
Two-way mode uses `rclone bisync`; concurrent edits become conflict copies.

For one-way folders, deleted or overwritten Drive files are parked under:

```text
cloudfs/.archive/<hostname>/<YYYY-MM-DD>/<original-path>
```

Archives older than 30 days are cleaned automatically. Drive trash and file
versions provide an additional safety layer.

cloudfs refuses nested sync roots and paths that contain or live inside any
cloudfs mount. This prevents duplicate watches and remote-to-remote loops.

## SSH servers

First create and test a normal OpenSSH alias:

```sshconfig
Host vps
    HostName vps.example.com
    User deploy
    IdentityFile ~/.ssh/id_ed25519
```

```bash
ssh vps
cloudfs server add vps
```

`cloudfs server add` explicitly registers the alias, enables its mount at
login, mounts the remote user's home directory at `~/vps`, and adds it to the
Files sidebar. cloudfs never scans or mounts every entry in `~/.ssh/config`.

Server commands:

```bash
cloudfs server list
cloudfs server open vps
cloudfs server unmount vps
cloudfs server mount vps
cloudfs server remove vps
```

Mount services are noninteractive. Password-protected keys must already be
available through `ssh-agent`, and the host key should be accepted by running
`ssh <alias>` once before adding the server.

Removing a server only removes its cloudfs registration, mount, service
instance, and sidebar bookmark. Remote files and `~/.ssh/config` are untouched.

## Tray and file manager

The tray icon shows Drive sync state and reports a failed server mount as an
error. Its menu provides:

- watched Drive folders and manual sync;
- Google Drive access;
- registered server mount/open/unmount/remove actions;
- an SSH server alias entry dialog;
- sync pause/resume and logs.

In Nautilus, right-click a local folder and choose **Sync to Google Drive**.
The action is hidden inside Google Drive and registered server mounts. Nemo
users receive the same add action under **Scripts**.

## Configuration

```text
~/.config/cloudfs/folders.conf   Google Drive sync folders
~/.config/cloudfs/servers.conf   explicitly registered SSH aliases
~/.config/cloudfs/environment    settings loaded by CLI and systemd services
~/.local/state/cloudfs/          sync state and bisync markers
```

Environment overrides:

- `CLOUDFS_REMOTE` - rclone Drive remote, default `gdrive`
- `CLOUDFS_ROOT` - default Drive sync root, default `cloudfs/<hostname>`
- `CLOUDFS_DRIVE_MOUNT` - Drive mountpoint, default `~/GoogleDrive`
- `CLOUDFS_QUIET_SECONDS` - local change debounce, default `15`
- `CLOUDFS_ARCHIVE_DAYS` - archive retention, default `30`

Edit `~/.config/cloudfs/environment` to change these persistently, then run
`systemctl --user daemon-reload` and restart the relevant cloudfs services.

Default sync excludes include `node_modules`, `.cache`, `__pycache__`,
`.venv`, `target`, `build`, `*.tmp`, and `*.swp`.

## Service control

```bash
cloudfs pause
cloudfs resume
cloudfs status
cloudfs log
```

To uninstall from a clone:

```bash
./uninstall.sh
```

Uninstall stops all mounts and removes installed cloudfs files. It preserves
cloudfs configuration/state, SSH configuration, rclone remotes, and all remote
files.
