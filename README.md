# Dockerd

A native macOS taskbar that runs alongside, or in place of, the system Dock. You choose per app whether its windows are grouped into one entry or shown as separate entries.

Example: show every VS Code window as its own entry labelled with the repo name, and keep Safari and Terminal as one entry each with a window list.

- Swift + AppKit, macOS 13 or later, public APIs only, no third-party dependencies.
- Menu bar utility with no Dock icon of its own and a settings window.
- No network access, no screen capture, no telemetry. Settings are stored locally.

## Build and run

Requirements: Xcode or the Command Line Tools with Swift 6.2 or later.

```sh
swift build
scripts/test.sh
scripts/release.sh
open dist/Dockerd.app
```

- `scripts/test.sh` wraps `swift test`. With only the Command Line Tools installed, `swift test` can't find the Swift Testing macros, so the script adds the plugin path. With Xcode it simply runs `swift test`.
- `scripts/release.sh` produces `dist/Dockerd.app`. By default it is universal (arm64 + x86_64); set `UNIVERSAL=0` to build for the host architecture only. It is signed with a local `Dockerd Local Signing` certificate if one exists, which keeps the Accessibility grant across rebuilds, otherwise ad-hoc. Set `SIGN_IDENTITY` to choose an identity. Other variables: `VERSION` and `BUILD_NUMBER`.
- For a Developer ID build and notarization, see [docs/SIGNING.md](docs/SIGNING.md).

## Permissions

Dockerd needs **Accessibility** access to list, focus, minimize and restore other apps' windows. On first launch it shows an explanation and a **Grant Access…** button. You can also enable it under System Settings → Privacy & Security → Accessibility.

- Without access, the bar shows pinned launchers and nothing else. Dockerd checks again periodically, so granting access takes effect without a relaunch.
- If access is revoked while Dockerd is running, window entries are cleared and the explanation window reappears.
- Screen Recording is **not** requested. Window titles come from Accessibility, not from window capture, so hover previews show the icon, title and state rather than thumbnails.
- Run `scripts/make-signing-cert.sh` once and every later build keeps the grant. Without it, ad-hoc builds lose the grant on every rebuild, because macOS ties it to the code signature. Remove the old entry and grant access again, or create the one-time local certificate described in [docs/SIGNING.md](docs/SIGNING.md).
- While access is missing, the first entry in the bar is an orange warning. Click it to fix access.

## Using it

- **Clicking an entry**
  - App with one window: activates it.
  - App with several windows: opens a window list.
  - Window entry: activates that exact window.
  - Pinned app that isn't running: launches it.
- **Right-click** an entry for window actions (Minimize, Restore, Close Window), Hide, Quit, Show in Finder, Pin to Dockerd / Unpin from Dockerd and **Window Grouping** (Use Default / Group Windows / Show Each Window Separately), and on window entries a **Show Window Titles** toggle.
- **Drag** to reorder.
  - Moving a pinned app or a separator saves its position.
  - Moving any other running app keeps it in place until Dockerd quits; after a restart, unpinned apps return to launch order.
  - Dragging no longer pins an app: use right-click → Pin to Dockerd, or drop a `.app` from Finder onto the bar.
- **Separators:** add them with right-click → Add Separator After (on a pinned app) or with the separator button in Settings → Pinned. Drag them like pinned apps, and remove them with right-click → Remove Separator. Settings → General → "Show a separator after pinned apps" adds an automatic divider, like the Dock's.
- **Downloads and Trash** sit at the end of the bar, after a separator, like the Dock.
  - Clicking Downloads lists your 20 most recent downloads. macOS asks once for permission to read the folder.
  - Clicking Trash opens it in Finder. Right-click → Empty Trash… asks for confirmation, then has Finder empty it; macOS asks once to let Dockerd control Finder.
  - You can turn either off in Settings → General or from its right-click menu. Dragging files onto them isn't supported.
- **Open at login:** turned on the first time Dockerd runs. Turn it off in Settings → General or in System Settings → General → Login Items. The login item points at wherever the app was when it was registered, so keep `Dockerd.app` in one place (ideally `/Applications`).
- **Notification badges:** unread counts (Mail, Messages, Slack…) show as a red badge, copied from the system Dock through Accessibility every 2 seconds. This works while the system Dock is hidden. The grey badge at the bottom-right of a grouped app is its window count.
- **Full screen:** when the focused window on a display is in full screen, that display's bar hides like the system Dock. Push the pointer against the screen edge to bring it up. It returns when you leave full screen.
- **Launch feedback:** a pinned app pulses after you click it until it is running, or for up to 30 seconds.
- **Keyboard:** menu bar → Navigate Dock with Keyboard. Use the arrow keys, Home/End, Return or Space to activate, `m` for the context menu and Esc to leave.
- **Settings tabs**
  - General: edge, icon size, spacing, titles, auto-hide, hover previews, Restore Defaults.
  - Grouping: default mode and per-app rules.
  - Pinned: the pinned apps and their order.
  - Displays: which displays get a bar, where window entries appear, current-Space-only.
  - Access: permission status and system Dock instructions.

Grouping rules are keyed by exact bundle ID, so VS Code, VS Code Insiders, VSCodium and Cursor each have their own rule. Rule changes apply immediately.

Settings file: `~/Library/Application Support/Dockerd/settings.json`. Writes are atomic. An unreadable file is renamed to `settings.corrupt-<timestamp>.json` and Dockerd starts with the defaults.

## The system Dock

macOS has no public API to add entries to the real Dock or to remove it, so Dockerd is a separate bar. Dockerd never injects into or patches the Dock.

**Settings → Access → "Hide the system Dock while Dockerd is running"** does this for you:

- **Turning it on:** Dockerd saves your current Dock auto-hide settings, then turns auto-hide on with a 1000-second delay and restarts the Dock (`killall Dock`). That's the only time Dockerd touches the Dock.
- **Turning it off or quitting Dockerd:** your saved settings are put back and the Dock restarts again. The next time Dockerd launches, it hides the Dock again.
- **Restore Defaults** also turns hiding off and brings the Dock back.

If Dockerd crashes or is force-quit while the Dock is hidden, open Dockerd and turn the option off, or run `scripts/restore-system-dock.sh`. That script resets auto-hide to the macOS defaults; it doesn't know your old values.

## Architecture

```
Sources/
  DockerdCore/          pure logic, no windows, unit tested
    Models/             WindowID, WindowInfo, AppInfo, PinnedApp, DockItem
    Grouping/           GroupingPolicy (default + per-bundle rules), TaskbarLayoutBuilder
    Settings/           Settings (Codable, clamped, tolerant decoding), SettingsStore (JSON, debounced atomic save)
    WindowManagement/   WindowStore (stable identity, stale removal), CGWindowMatcher
    Displays/           DisplayInfo, window→display assignment, dock display selection, panel geometry
    Permissions/        PermissionStateMachine (denied / granted / revoked)
  Dockerd/              AppKit app
    WindowManagement/   AXElement helpers, WindowTracker (NSWorkspace + AXObserver), WindowActions, CGWindowSnapshot
    Dock/               DockController, DockPanelController/DockPanel, DockBarView, DockItemView, WindowListPanel, HoverCard
    Settings/           SettingsWindowController
    Permissions/        PermissionController, OnboardingWindowController
    App/                AppDelegate, StatusItemController, main
```

Data flow: `WindowTracker` → `WindowStore` → `TaskbarLayoutBuilder` (with `GroupingPolicy`, pins and display settings) → a `DockItem` list per display → `DockBarView`. A settings change triggers the same rebuild, which is why rules apply live.

**Window discovery.** Changes are event driven:

- `NSWorkspace` notifications: launch, terminate, activate, hide/unhide, Space change.
- Per-app `AXObserver` notifications: window created, destroyed, title change, minimize/restore, move/resize, focus change.

Events are coalesced, at most every 80 ms per app. A slow sweep every 8 seconds catches missed events. Only regular (Dock-visible) apps are tracked, and only standard windows: no panels, palettes or tiny utility windows.

**Window identity.** Each window has a Dockerd `WindowID`, keyed by its `AXUIElement`, so two windows with identical titles stay distinct. A `CGWindowID` is matched by process ID and bounds. It is used for on-screen/other-Space state and to re-bind a window whose Accessibility element was recreated. No private APIs are used, including `_AXUIElementGetWindow`.

**Activation.** Restore if minimized → set main → `AXRaise` → set the app frontmost → raise again shortly after. If that fails, Dockerd falls back to `NSRunningApplication.activate`. The bar is a non-activating panel, so clicking it never takes focus from the app you are using.

## Limitations

macOS's public APIs can't do the following, so Dockerd doesn't claim to:

- **Spaces.** There is no public API for which Space a window is on. If a window's Accessibility element disappears but its window still exists, it is shown as "on another Space". Some apps keep reporting windows on other Spaces as normal, so they look like current-Space windows. Whether clicking such a window switches Space depends on the macOS setting "When switching to an application, switch to a Space with open windows".
- **Full-screen apps.** The bar is set to appear over full-screen Spaces, but macOS doesn't always allow it.
- **No reserved screen space.** Apps can't reserve a screen edge the way the Dock does, so maximized windows can sit under the bar. Use auto-hide, or leave a margin.
- **No thumbnails.** Live window previews would need Screen Recording, which Dockerd deliberately doesn't request.
- **Incomplete Accessibility support.** Apps with poor Accessibility support (some Java, Electron or game windows) may report no windows or wrong titles. They still appear as a single app entry.
- **Minimize animation.** macOS always animates a minimized window into the system Dock's position, even when the Dock is hidden. No public API changes where it lands. With the bar at the bottom it lands near the bar, but not on the entry.
- **Dock-only features.** Stacks, bouncing for attention and download progress bars aren't available through public APIs. Badges are read from the system Dock, so an app that isn't running and isn't in the system Dock shows none.
- **No dragging files onto running apps.** Dragging a `.app` onto the bar pins it.
- **Mission Control and app switching** (⌘Tab) are unaffected and still belong to the system.
- **No top edge.** The bar can sit at the bottom, left or right. The top edge belongs to the menu bar.
- **No launch at login yet.** Add Dockerd to System Settings → General → Login Items yourself.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Bar shows only pinned apps | Accessibility not granted. Use the menu bar status item → "Accessibility: Not Allowed — Fix…". |
| Granted, but still nothing after a rebuild | The signature changed. Remove Dockerd from the Accessibility list, then add it again (see [docs/SIGNING.md](docs/SIGNING.md)). |
| A window is missing | Some apps create windows lazily. Interact with the app or wait a few seconds for the sweep. Check that it is a standard window and not a panel. |
| Bar is missing on a display | Settings → Displays: check the display mode or selection. Menu bar → Show Dock if it was hidden. |
| Bar covers content | Turn on auto-hide, or reduce the icon size. |
| System Dock gone and you want it back | Settings → Access → turn off "Hide the system Dock…", or quit Dockerd. If Dockerd crashed, run `scripts/restore-system-dock.sh`. |
| Settings look reset | A corrupt file was moved to `settings.corrupt-*.json` in the settings folder. |

Logs: `log stream --predicate 'subsystem == "me.santoshpanna.Dockerd"'`.

## Tests

- `scripts/test.sh` runs the unit tests (Swift Testing). They cover:
  - grouping resolution and bundle-ID variants
  - per-window entries, including identical titles
  - rule add/update/delete and persistence
  - restore defaults and corrupt-file recovery
  - stale window removal, minimize/restore and other-Space retention
  - CG window matching
  - display assignment and display changes
  - panel geometry
  - permission denial and recovery
- Scenarios that need real apps, Spaces or hardware are in [docs/MANUAL_TESTS.md](docs/MANUAL_TESTS.md).
