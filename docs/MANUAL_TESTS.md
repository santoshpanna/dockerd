# Manual test plan

These scenarios depend on real apps, real windows, Spaces and hardware, so the unit tests can't cover them reliably. Run them against `dist/Dockerd.app` after `scripts/release.sh`.

Setup: macOS 13 or later, with VS Code, Safari and Terminal installed. A second display is needed for section 6.

## 1. First launch and permission

1. Remove any old Dockerd entry from System Settings → Privacy & Security → Accessibility.
2. `open dist/Dockerd.app`.
   - Expect: a menu bar icon, no Dock icon for Dockerd, and the onboarding window explaining Accessibility.
   - Expect: the bar shows pinned launchers only; no windows are listed yet.
3. Click **Grant Access…** and enable Dockerd in System Settings.
   - Expect: within about 2 seconds the onboarding window closes and running apps appear in the bar. No relaunch is needed.
4. Menu bar → status line reads "Accessibility: Allowed".

## 2. Grouping (definition of done)

1. Open five VS Code windows on five different folders. Open three Safari windows and two Terminal windows.
2. With defaults, expect one entry each for VS Code, Safari and Terminal. Clicking an entry with more than one window opens a list of its windows.
3. Settings → Grouping → **+** → VS Code → set its mode to **Separate**.
   - Expect: right away, without a restart, five VS Code entries, each labelled with its window title.
4. Click each VS Code entry in turn.
   - Expect: that exact window comes to the front and gets focus, including when two windows have the same title (for example two "Welcome" windows).
5. Safari and Terminal are still one entry each. Click Safari, then a window in the list. Expect that window to activate.
6. Right-click a VS Code entry → Window Grouping → **Use Default**. Expect the entries to collapse back into one.
7. Quit and relaunch Dockerd. Expect the rule from step 3 to still be there (settings live in `~/Library/Application Support/Dockerd/settings.json`).
8. Settings → General → **Restore Defaults…**. Expect the rules to be cleared and everything grouped again.

## 3. Window state

1. Minimize a separate VS Code window (⌘M).
   - Expect: its entry stays, dimmed, with the minimized badge.
2. Click it. Expect it to restore and take focus.
3. With "Clicking the focused window minimizes it" on, click the focused window's entry. Expect it to minimize.
4. Close a window. Expect its entry to disappear within a second.
5. Quit VS Code. Expect all its entries to go away; a pinned VS Code becomes a launcher.
6. Hide Safari (⌘H). Expect its entry to show as hidden; clicking it shows Safari again.

## 4. Pinning and launching

1. Drag Calculator.app from Finder onto the bar. Expect it to be pinned at the drop position.
2. Click it. Expect Calculator to launch and the launcher to become a running entry.
3. Drag a pinned entry to a new spot. Relaunch Dockerd and expect it to stay there.
4. Drag a running, unpinned app between two others. Expect it to stay there while windows open and close, and when the app quits and relaunches. Relaunch Dockerd and expect unpinned apps back in launch order.
5. Right-click a pinned app → Add Separator After. Drag the separator, relaunch, and expect it to stay where you put it. Right-click it → Remove Separator.
6. Settings → General → "Show a separator after pinned apps". Expect a divider between pinned and other apps; there is none when no unpinned app is running.
7. Right-click → **Unpin**.

## 5. Spaces and full screen (best effort)

1. Create a second Space and move a VS Code window there.
   - Expect: with default settings, that window's entry shows the "other Space" badge.
   - Expect: clicking it switches to that Space and focuses the window. Whether macOS switches depends on your "When switching to an application, switch to a Space…" setting.
2. Settings → Displays → enable **Only show windows from the current Space**. Expect windows on the other Space to drop out of the bar after the Space change.
3. Make an app full screen. The bar may or may not appear over it. Either is acceptable; it must not crash or steal focus.

## 6. Multiple displays

1. Connect a second display. Expect a bar to appear on it within about a second.
2. Move a VS Code window to the second display. With "Show window entries" set to "On the display the window is on", expect its entry to move to that display's bar only.
3. Switch it to "On every dock (duplicates)". Expect all windows on both bars.
4. Settings → Displays → **Selected displays**, untick one. Expect its bar to disappear.
5. Unplug the display. Expect its bar to be removed with no crash, and its windows to appear on the remaining bar.
6. Change resolution, or the edge between bottom, left and right. Expect the bar to reposition.

## 7. Focus and keyboard

1. Type in TextEdit, then move the mouse over the bar and hover entries.
   - Expect: TextEdit keeps focus and the hover card appears after a moment.
2. Menu bar → **Navigate Dock with Keyboard**. Use the arrow keys, Return to activate, "m" for the context menu, and Esc to leave.
3. Turn on VoiceOver. Expect each entry to read its app or window name and state.

## 8. Permission revocation

1. While Dockerd runs, turn it off in the Accessibility settings.
   - Expect: within about 5 seconds the onboarding window reappears and window entries clear.
   - Expect: launchers stay, and nothing crashes.
2. Turn access back on. Expect windows to come back without a relaunch.

## 9. Hiding the system Dock

1. Note `defaults read com.apple.dock autohide` and `defaults read com.apple.dock autohide-delay`. Either key may not exist.
2. Settings → Access → turn on "Hide the system Dock while Dockerd is running". Expect the Dock to restart and stop appearing at the screen edge.
3. Quit Dockerd. Expect the Dock to return, and both values to match step 1, including keys that didn't exist.
4. Launch Dockerd. Expect the Dock to be hidden again. Turn the option off and expect it back.
5. With hiding on, use Settings → General → Restore Defaults. Expect the Dock back and the option off.
6. Without turning the option on, Dockerd must never restart the Dock or change its settings.
