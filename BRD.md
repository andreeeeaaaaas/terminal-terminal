---
---

# Terminal Terminal

> A floating macOS departure board that shows your running dev servers as flights, built as a portfolio piece.

**Status:** Building
**Last updated:** 2026-10-12

## How to use this document

This BRD is the source of truth for what is being built. Where it conflicts with
general conventions, house style, or a CLAUDE.md in this repo, this document wins.

- Locked Choices are non-negotiable. Do not substitute, upgrade, or suggest
  alternatives unless explicitly asked.
- Rules apply across the whole codebase, without exception.
- Not Doing means not doing. Do not implement it, do not scaffold for it.
- If a decision is not covered here and would be expensive to reverse, stop and
  ask. Add it to Open Questions rather than assuming.
- Build one item from Scope at a time unless told otherwise.
- When a decision changes, update this document before writing code against it.

## 1. Overview

**The problem**
Dev servers and long-running background tasks (watchers, builds) get left running in old terminal tabs, quietly holding ports and memory. When several are up, there is no glanceable way to tell what is running or which project is on which port without running `lsof` by hand.

**Who it's for**
The author, as a portfolio piece. Craft and motion quality matter as much as utility: it should be a delightful object first and a useful tool second.

**What it does**
A menu bar app that floats a small, always-on-top split-flap departure board over the desktop. Each row is either a process listening on a local TCP port or a recognised dev tool running in the background for over 5 minutes (GATE shows `--`). Columns are GATE (port, left-aligned), FLIGHT, PID, STATUS and TIME (uptime as `hh:mm:ss` ticking every second, or `hh:mm` with seconds off). Rows flip in when a process starts, flip to DEPARTED when it stops, and can be killed from the board. Hovering the GATE or FLIGHT of a recognised web server flips GATE to `OPEN↗` (on accent tiles in the flap style, in the accent colour in the others); clicking either opens `http://localhost:<port>` in the default browser, or the exact bound address (`127.0.0.1`, `[::1]`) when another row listens on the same port.

Status is BOARDING (just appeared), RUNNING, IDLE (near-zero CPU for about a minute) or DEPARTED (gone, about to be removed). While a kill is in progress: CLOSING (SIGTERM sent), DELAYED (still alive after 3 seconds, awaiting force-quit confirmation), DENIED (signal refused).

FLIGHT reads as airline plus destination: the label, then the project folder (from the `node_modules` path or working directory), so you can tell which project is which.

The board appears automatically when the first process arrives and hides only when the user toggles it from the menu bar or clicks the minimise button on the board. With "Appear on new server" on, every new arrival brings it back, even after hiding. With nothing running, it shows the header row over empty flap tiles.

**Why not the existing option**
`lsof`, Activity Monitor and port-manager menu bar apps already list ports. None of them are glanceable or fun to look at, and building it is the point.

**Done means**
The floating board shows real listening ports, refreshes on a poll, animates character changes as split-flaps, toggles from the menu bar icon, and kills a process from a row (SIGTERM, then SIGKILL after confirmation if it survives about 3 seconds).

**Scope**
- Menu bar icon and floating board panel
- Port and process scanner
- Background dev-tool detection
- Process label heuristics ("airline")
- IDLE detection
- Auto-show on first arrival, or on every arrival when set
- Empty board state
- Split-flap character and text views
- Row arrival and departure animations
- Hover-to-kill control
- Click GATE to open web servers in the browser
- Settings popover (style, display, accent colour, seconds, poll interval, show all ports, appear on new server, reset position)
- Selectable board styles
- Remembered board position
- README (permissions, extending label heuristics)
- Universal build and unsigned GitHub release zip

## 2. Locked Choices

| Layer | Choice | Notes |
|---|---|---|
| Language | Swift | |
| Framework | SwiftUI, with AppKit where SwiftUI can't | `NSStatusItem` for the menu bar, borderless non-activating `NSPanel` for the board |
| Styling | Selectable styles: split-flap, plain mono, LED dot-matrix | Default is Charcoal: cream characters on dark split-flap tiles with a hairline hinge, SF Mono. Styles are `BoardTheme` presets; the user picks one in settings and can override its display and accent colour |
| State | `ObservableObject` / `@Published` | `@Observable` needs macOS 14 |
| Data | `lsof -iTCP -sTCP:LISTEN -P -n` and `ps -axww -o pid,ppid,uid,etime,%cpu,tty,command` via `Process` | Polled every 2 seconds by default. One `ps` call covers port owners, background tasks, CPU and parent chains. `lsof -d cwd` once per new PID for the project folder |
| Persistence | `UserDefaults` | Board position, settings |
| Package manager | Swift Package Manager | Executable target, opens directly in Xcode. Zero dependencies |
| Distribution | Unsigned universal build (arm64 + x86_64), shared as a zip on GitHub Releases | Ad-hoc signed; users clear Gatekeeper with Open Anyway. No Dock icon (`LSUIElement` / `.accessory` activation policy) |

**Pinned versions**
- Deployment target: macOS 13

## 3. Rules

**Always**
- Display text in uppercase and only from the flap glyph set (A–Z, 0–9, space, `: . - /`, plus `↗` for the open control). Map `_` to `-` and anything else to a space.
- Run scans off the main thread and publish results on the main actor.
- Invoke `lsof` and `ps` by absolute path with argument arrays. Send signals with the `kill(2)` syscall, not the `kill` command.
- Show only the current user's processes. Hide processes spawned by GUI apps (Raycast, editors) and anything inside an `.app` bundle or system directory, unless a label rule matches it.
- Honour Reduce Motion: characters settle instantly, rows fade instead of flipping.
- Keep the panel non-activating: interacting with the board never steals focus from the frontmost app.

**Never**
- Add a third-party dependency.
- Run commands through a shell (`sh -c`) or interpolate process data into a command string.
- Send any signal without an explicit user click, or SIGKILL without a confirmation.
- Add windows, sidebars or chrome beyond the board and the settings popover.

**Patterns**
- `SplitFlapCharacter` owns one cell's change sequence and draws it in the theme's cell style (flap, plain or dots); `SplitFlapText` composes cells for a field. Rows are built only from `SplitFlapText`.
- Scanner → diff → view model → views. The scanner knows nothing about UI; the diff assigns BOARDING / RUNNING / DEPARTED.
- Label heuristics live in one table-driven file, ordered most to least specific, with process name as the fallback. A rule's `web` flag marks servers whose port opens in a browser; generic interpreters (NODE, PYTHON) are never flagged. The same table decides which portless processes count as background dev tools; shells, editors and one-shot CLIs (git, plain ssh) never match. SSH port forwards (`-L`, `-R`, `-D`) do, since they're long-running.

## 4. Not Doing

**Non-goals**: product direction this deliberately excludes
- Not a process manager or launcher: it never starts, restarts or configures servers.
- Not a log viewer or terminal.
- macOS only.

**Out of scope**: not in this build, may come later
- Developer ID signing, notarisation, Homebrew cask, App Store, auto-update.
- UDP sockets and remote hosts.
- Automated tests.

## 5. Open Questions

Flag and pause on these. Do not assume an answer.

None open.
