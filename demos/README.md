# Demos

Recordings and renders of the board, for the README, releases and portfolio.

- `*.demo.yaml`: demo plans. Record one with `skill/demo-video/scripts/demo-video run demos/<name>.demo.yaml`; takes go to `out/`.
- `screens/`: still renders, from `swift run TerminalTerminal --screens demos/screens`.
- `skill/demo-video/`: a copy of the demo-video skill that records the plans. The live copy is in the [skills repo](https://github.com/andreeeeaaaaas/skills/tree/main/skills/demo-video); refresh this one with `rsync -a --delete --exclude .build ~/skills/skills/demo-video demos/skill/`.

`out/` and `screens/` are generated and not committed. Recording needs Screen Recording and Accessibility permission for your terminal, and moves the pointer during a take.
