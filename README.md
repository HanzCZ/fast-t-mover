# FastTMover

Small macOS menu-bar app that moves files matching a glob (default `*.torrent`)
from a local source folder to an SMB share. Designed to run quietly in the
background and effectively trigger once per day after wake.

## What it does

1. On a schedule (≈ on wake, max 1×/day) or on-demand, scans a source folder.
2. Mounts an SMB share via AppleScript (uses macOS Keychain for credentials).
3. Moves matched files into a destination subfolder on the share.
4. Logs everything to `~/.local/state/fast_t_mover/torrent_mover.log`.

A once-per-day lockfile (`~/.local/state/fast_t_mover/last_run_date`) ensures
the work only happens once daily even though the LaunchAgent ticks more often.

## Install

### Build from source

Requires macOS 13+ and Swift 5.7+ (CommandLineTools is enough).

```bash
./build_app.sh
cp -R dist/FastTMover.app /Applications/
open /Applications/FastTMover.app
```

A tray icon (`tray.and.arrow.up`) appears in the menu bar.

### One-time SMB setup

1. In Finder press `⌘K`, enter your SMB URL (e.g. `smb://192.168.0.249/shdd`).
2. Authenticate and tick **Remember this password in my keychain**.

The app's `mount volume` call will then succeed silently.

## Use

Click the menu bar icon:

- **Run Now** — execute once with the daily lock.
- **Run Now (debug)** — bypass the lock, verbose, also matches files with the
  pattern body anywhere in the name (for testing with renamed files).
- **Auto-run on wake** — install/remove the LaunchAgent.
- **Settings…** — configure source folder, SMB URL, destination subfolder,
  file pattern.
- **Show Log** — open the log file.

## Config

Settings are saved via `@AppStorage` (UserDefaults) and mirrored to
`~/.config/fast_t_mover/config` (key=value) which the worker script sources.

```
SOURCE_DIR='/Users/you/Downloads'
SMB_URL='smb://192.168.0.249/shdd'
DEST_SUBDIR='new-torrents'
PATTERN='*.torrent'
ALLOWED_SSIDS=''   # comma-separated whitelist; empty = any network
```

## Network gate & error recovery

The SMB host may only be reachable from specific networks. To avoid noisy
failures when away:

- **Allowed Wi-Fi SSIDs**: if set, the script exits cleanly (no error) when
  on any other Wi-Fi. Leave empty once a VPN provides reachability from
  anywhere.
- **Soft mount failures**: if the SMB mount fails (off-network, VPN down),
  the script exits 0 without taking the daily lock. The next launchd tick
  (every 15 min) retries automatically.
- The daily lock is only taken on success (or when there was nothing to do
  *while on an allowed network*).

## Layout

```
Sources/FastTMover/
    App.swift            Menu bar entry + menu items
    SettingsView.swift   Settings window
    Config.swift         Writes the config file
    Runner.swift         Spawns the worker script
    LaunchAgent.swift    Install/uninstall the LaunchAgent
move_torrents.sh         The worker (bash) — usable standalone too
Info.plist               App bundle metadata (LSUIElement)
build_app.sh             swift build + .app assembly + ad-hoc codesign
```

## Standalone (no app)

The script works on its own:

```bash
./move_torrents.sh --debug
```

It reads the same config file the app writes, falling back to built-in
defaults if absent.

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.hanak.torrentmover.plist
rm ~/Library/LaunchAgents/com.hanak.torrentmover.plist
rm -rf /Applications/FastTMover.app
rm -rf ~/.config/fast_t_mover ~/.local/state/fast_t_mover
defaults delete com.hanak.fasttmover
```
