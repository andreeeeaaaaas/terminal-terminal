# Demos

Recordings and renders of the board, for the README, releases and portfolio.

- `*.demo.yaml`: demo plans. Record one with the [demo-video skill](https://github.com/andreeeeaaaaas/skills/tree/main/skills/demo-video): `~/.claude/skills/demo-video/scripts/demo-video run demos/<name>.demo.yaml`; takes go to `out/`.
- `board.png`: the README image, copied from `screens/board-01-charcoal.png`.
- `screens/`: still renders, from `swift run TerminalTerminal --screens demos/screens`.
- `web/index.html`: an interactive HTML recreation of the Charcoal board for the portfolio site, embedded by iframe; `web/preview.html` frames it the way the site does. The live copy is `assets/demos/terminal-terminal/index.html` in the site repo: copy it over after each change.

`out/` and `screens/` are generated and not committed. Recording needs Screen Recording and Accessibility permission for your terminal, and moves the pointer during a take.
