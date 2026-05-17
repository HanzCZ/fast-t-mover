# FastTMover

Small macOS menu-bar app that moves files matching a glob (default `*.torrent`)
from a local source folder to an SMB share. Designed to run quietly in the
background and trigger once per configurable interval (default: once a day)
on the first allowed-Wi-Fi tick after wake.

## What it does

1. On a schedule (LaunchAgent ticks every 15 min) or on-demand, scans a source folder.
2. Optional Wi-Fi gate: only run when connected to a whitelisted SSID.
3. Mounts an SMB share via AppleScript (uses macOS Keychain for credentials).
4. Moves matched files into a destination subfolder on the share.
5. Posts a native macOS notification (green ✓ / red ✗ / blue ⓘ depending on outcome).
6. Logs everything to `~/.local/state/fast_t_mover/torrent_mover.log`.

A timestamp lockfile (`~/.local/state/fast_t_mover/last_run_ts`) gates work to
the configured minimum interval; off-network ticks and mount failures exit
cleanly without taking the lock so the next tick retries.

## Install

### Prereqs

- macOS 13 or newer
- Xcode Command Line Tools — `xcode-select --install` if missing
- (Optional) `gh` CLI authenticated, or just `git clone` over HTTPS

### A) Download the .dmg (no toolchain needed)

Grab the latest pre-built `.dmg` from
[**Releases**](https://github.com/HanzCZ/fast-t-mover/releases/latest),
open it, and drag **FastTMover.app** to **Applications**.

Because the build is ad-hoc signed, the first launch needs a Gatekeeper
override: **right-click the app → Open → Open**. Subsequent launches are
normal.

### B) Build from source (one command)

Used for development and for installing the bleeding-edge `main`. The same
command works for the first install and for every update — it quits any
running copy, rebuilds, replaces `/Applications/FastTMover.app`, and
relaunches.

```bash
# first time:
git clone https://github.com/HanzCZ/fast-t-mover.git
cd fast-t-mover

# every time (including updates):
git pull
./install_app.sh
```

You should see **FTM** + a disk icon in the menu bar within a second.

If the icon in Finder/Notification banner looks stale after an update, force a
cache refresh:

```bash
killall Dock Finder NotificationCenter usernoted 2>/dev/null
```

### First-run setup

1. **SMB credentials** — in Finder press `⌘K`, enter your SMB URL (e.g.
   `smb://192.168.0.249/shdd`), authenticate, tick **Remember this password
   in my keychain**. The app's `mount volume` call then succeeds silently.
2. **Notification permission** — macOS will prompt the first time the app
   tries to post. Click **Allow**. If you missed it: System Settings →
   Notifications → **FastTMover** → Allow Notifications + Banner style.
3. **Settings** — open **FTM → Settings…**:
   - Source folder
   - SMB URL + destination subfolder
   - File pattern (default `*.torrent`)
   - Allowed Wi-Fi SSIDs (comma-separated; empty = any network)
   - Minimum interval (Once a day / 12h / 4h / 1h / Every wake)
   - Toggle **Run automatically (≈ on wake)** — installs the LaunchAgent

## Use

Click the menu bar item:

- **Run Now** — execute once, honouring the configured interval.
- **Run Now (debug)** — bypass the interval lock, verbose, also matches files
  with the pattern body anywhere in the name (for testing with renamed files).
- **Test Notification** — post a sample success banner to verify permissions.
- **Auto-run on wake** — install/remove the LaunchAgent.
- **Settings…** — full configuration window.
- **Show Log** — open the log file.

## Config

Settings are saved via `@AppStorage` (UserDefaults) and mirrored to
`~/.config/fast_t_mover/config` (key=value) which the worker script sources.

```
SOURCE_DIR='/Users/you/Downloads'
SMB_URL='smb://192.168.0.249/shdd'
DEST_SUBDIR='new-torrents'
PATTERN='*.torrent'
ALLOWED_SSIDS=''     # comma-separated whitelist; empty = any network
INTERVAL_HOURS=24    # 0 = every tick, 24 = once a day
```

## Network gate & error recovery

The SMB host may only be reachable from specific networks. To avoid noisy
failures when away:

- **Allowed Wi-Fi SSIDs**: if set, the script exits cleanly (no error) when
  on any other Wi-Fi. Leave empty once a VPN provides reachability from
  anywhere.
- **Soft mount failures**: if the SMB mount fails (off-network, VPN down),
  the script exits 0 without taking the lock. The next launchd tick
  (every 15 min) retries automatically.
- The lock is only taken on success (or when there was nothing to do
  *while on an allowed network*).

## Layout

```
Sources/FastTMover/
    App.swift                  Menu bar entry + menu items
    SettingsView.swift         SwiftUI settings form
    SettingsWindow.swift       NSWindowController hosting the settings view
    Config.swift               Writes the config file + SSID helpers
    Runner.swift               Spawns the worker script
    LaunchAgent.swift          Install/uninstall the LaunchAgent
    NotificationManager.swift  UNUserNotificationCenter + queue file watcher
move_torrents.sh               The worker (bash) — usable standalone too
tools/generate_icon.swift      Generates the 1024x1024 app icon master PNG
Info.plist                     App bundle metadata (LSUIElement)
build_app.sh                   swift build + .app assembly + icon + ad-hoc codesign
```

## Standalone (no app)

The script works on its own:

```bash
./move_torrents.sh --debug
```

It reads the same config file the app writes, falling back to built-in
defaults if absent. Notifications posted via the queue file are picked up
the next time the menu-bar app launches; without the app, an `osascript`
fallback is attempted.

## Uninstall

```bash
osascript -e 'tell application "FastTMover" to quit' 2>/dev/null
launchctl unload ~/Library/LaunchAgents/com.hanak.torrentmover.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.hanak.torrentmover.plist
rm -rf /Applications/FastTMover.app
rm -rf ~/.config/fast_t_mover ~/.local/state/fast_t_mover
defaults delete com.hanak.fasttmover 2>/dev/null
```
