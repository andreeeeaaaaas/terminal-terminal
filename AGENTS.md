# AGENTS.md

Guidance for coding agents working in this repository.

`BRD.md` is the source of truth for scope, locked choices and rules. Read it first. Where it conflicts with this file, the BRD wins.

## Commands

```sh
swift build                                   # debug build
swift run                                     # launch the menu bar app
./scripts/bundle.sh                           # release build → build/Terminal Terminal.app (LSUIElement, ad-hoc signed)
swift run TerminalTerminal --scan [--all]     # print what the board would show, then exit
swift run TerminalTerminal --snapshot out.png # render the board with sample rows to a PNG, then exit
swift run TerminalTerminal --themes out.png   # render every style side by side, then exit
```

There are no tests (out of scope per the BRD). Verify visual changes with `--snapshot` and read the PNG. Verify scanner and heuristic changes with `--scan` against the real process table.

## Architecture

Swift package, single executable target `TerminalTerminal`, macOS 13+, Swift 5 language mode, no dependencies.

Data flows one way: **scanner → model → views**.

- `Scanner/ProcessScanner.swift` runs `lsof` and `ps` (absolute paths, no shell), builds the process tree, and decides which processes get a row. Noise filtering is here: same-user only, ports ≥ 1024, app-bundle/system paths, processes spawned by GUI apps (walks ancestors until an interactive shell), and process-tree collapse so `npm → sh -c → node vite` shows once. Runs off the main thread; not thread-safe, one scan at a time.
- `Scanner/LabelHeuristics.swift` is the table of `LabelRule`s mapping command lines to labels, plus the denylist and the project-name ("destination") logic. A rule match also makes a portless process eligible as a background task.
- `Board/BoardModel.swift` (`@MainActor ObservableObject`) runs a 250 ms tick loop: advances row phases and triggers a scan every `pollInterval`. It diffs scan results into `BoardEntry` rows keyed by PID plus command, and owns signals (re-checks the PID's command before `kill(2)`). Row lifecycle: `boarding → active → departed → clearing → removed`, with `closing → delayed → force quit` for kills.
- `Board/BoardTheme.swift` defines every selectable style: palette, typeface, cell metrics, cell style (`.flap`, `.plain`, `.dots`), optional row rules and per-column/per-status colours. Views read `\.boardTheme` from the environment; `ThemedBoard` in `AppDelegate.swift` injects the one picked in settings. Add a style by adding a static theme and listing it in `BoardTheme.all`. Settings can override a preset's display, accent and seconds via `BoardTheme.customised`, which rescales metrics and derives tiles or unlit dots the preset lacks. Column widths come from `theme.cells(_:)`, not `BoardColumn.cells`, because TIME narrows without seconds.
- `Flap/` is the character renderer. `SplitFlapCharacter` animates a cell through random glyphs to its target via `.task(id:)` (or straight to it with `scrambles: false`, used for clocks) and draws it with `FlapFace` (split-flap), `PlainCell` or `DotMatrixCell` (5×7 `DotFont`) per the theme. `SplitFlapText` composes cells into a fixed-width field. All board text goes through `FlapGlyphs.cells`, which uppercases and restricts to the glyph set; `DotFont` must cover every glyph in that set.
- `Board/BoardView.swift` and `BoardRow.swift` lay out columns (widths in cells, in `BoardColumn`). Empty slots render as blank tiles down to `minimumRows`. Departing rows flip to blank before collapsing.
- `App/` holds the AppKit shell. `AppDelegate` owns the status item and settings. Settings shows in `SettingsBubble`, a hand-positioned popover-style panel (Liquid Glass on macOS 26+, `NSVisualEffectView` vibrancy before; grows from the arrow on open) (`NSPopover` misplaces itself when anchored inside a floating panel near the screen bottom), anchored to the menu bar button or an `NSView` behind the board's gear. `BoardPanelController` hosts SwiftUI in a borderless non-activating `NSPanel`, sizes it from a SwiftUI size preference (top-left anchored, shrinks delayed until collapse animations finish), and persists the dragged position in `UserDefaults`.

## Gotchas

- Target is macOS 13: no `@Observable`, no two-parameter `onChange`, no `UnevenRoundedRectangle`. Drive animations with `.task(id:)`.
- The app is never active, so custom hover effects use `HoverTracker` (an `.activeAlways` `NSTrackingArea`) as a background, and the board's hosting view accepts first mouse. Don't replace these with `onHover`/defaults without testing in a running build.
- `ImageRenderer` can't draw `NSViewRepresentable`s. Anything AppKit-backed must be skipped when `\.flapStartsSettled` is true, or snapshots show yellow placeholders.
- Nothing activates the app: the board and settings bubble are non-activating panels. Settings closes via click and Escape monitors in `AppDelegate`, not app deactivation.
