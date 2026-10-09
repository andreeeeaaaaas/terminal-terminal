# Terminal Terminal

A floating split-flap departure board for macOS that shows your running dev servers and forgotten background tasks as flights.

```
GATE  FLIGHT             PID  STATUS    TIME
4321  ASTRO OCEANHEROE  7862  RUNNING   90:16:40
5173  VITE TERMINAL-UI 40211  BOARDING  00:21:00
--    TSC API          40388  IDLE      01:07:00
```

- **GATE**: listening port, or `--` for a background task with no port
- **FLIGHT**: what's running (the "airline") and which project (the destination)
- **STATUS**: BOARDING, RUNNING, IDLE (near-zero CPU for a minute), DEPARTED
- **TIME**: uptime as hours, minutes and seconds

## Run it

Requires macOS 13 or later and Xcode 15 or later. No dependencies.

```sh
open Package.swift                 # in Xcode, then Run (⌘R)
swift run                          # or from the terminal
./scripts/bundle.sh                # or build "build/Terminal Terminal.app"
```

The bundled app is ad-hoc signed and has no Dock icon. Move it to `/Applications` to keep it.

## Use it

- **Click the menu bar plane** to show or hide the board.
- **⌘-click or right-click it**, or click the gear on the board, for settings: board style, display (flap, LED, pixel, plain), accent colour, seconds, refresh interval, show all ports, reset the board position, quit. Picking a style resets display and accent to that style's own.
- **Drag the board** anywhere. It remembers where you put it.
- **Hover a row and click ×** to send SIGTERM. If the process is still alive after 3 seconds, the row turns DELAYED and asks before sending SIGKILL.

The board appears on its own when the first server starts, and stays until you hide it with the menu bar plane or the – button on the board.

## Permissions

None to grant. `lsof` and `ps` can read your own processes without Full Disk Access, Accessibility or Screen Recording.

- Only your own processes are shown. Root and other users' processes need `sudo` to see, and the app never asks for it.
- Signals only reach your own processes. Anything else shows DENIED.
- The app is not sandboxed, because a sandboxed app can't run `lsof`. That rules out the Mac App Store.

## What shows up

By default:

- **Port owners**: processes listening on TCP ports 1024 and above.
- **Background tasks**: recognised dev tools (watchers, builds, interpreters) with no port that have run for 5 minutes or more.

Hidden as noise:

- Apps and anything in a system directory (ControlCenter, Spotify, Figma helpers), unless a label rule recognises it (Ollama, Postgres.app, Docker).
- Processes started by a GUI app rather than a terminal, like Raycast extensions or editor language servers.
- MCP servers run by AI tools.
- Wrappers: `npm run dev` shows once, as the server it starts.

**Show all ports** in settings turns off the noise filter for port owners.

## Extending the labels

Rules live in `Sources/TerminalTerminal/Scanner/LabelHeuristics.swift`. Add a `LabelRule` to `rules`:

```swift
LabelRule("SANITY", .token("sanity")),             // a word in the command, by basename
LabelRule("DJANGO", .phrase("runserver")),         // a substring of the command line
LabelRule("JUPYTER", .tokenPrefix("jupyter")),     // jupyter, jupyter-lab, …
```

The first match wins, so put frameworks above the interpreters that run them. A matching rule also makes a portless process count as a background task. To hide something, add it to `hiddenExecutables` or `hiddenTokenFragments` in the same file.

To check what the board would show without opening it:

```sh
swift run TerminalTerminal --scan          # add --all to bypass the noise filter
swift run TerminalTerminal --snapshot board.png
```
