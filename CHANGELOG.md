# Changelog

All notable changes to this project will be documented in this file.

## [1.0.4] - 2026-11-24

### Changed
- Picks up game-common 1.19.0: with the Dashboard installed, the title bar's
  close icon becomes a house that goes back to it.

## [1.0.3] - 2026-11-24

### Changed
- Picks up game-common 1.18.0: a status line cut off with "…" opens in full
  when tapped, so a long hint can be read.

## [1.0.2] - 2026-11-18

### Changed
- Picks up game-common 1.17.0 (a board redraw fix used by chess, binairo and
  tatami; no change in this game).

## [1.0.1] - 2026-11-18

### Fixed
- The guide's pencil marks, and rubbing them out, show at once.

## [1.0.0] - 2026-11-10

### Added
- First release: a cooperative maze game for two players with a reader
  each. Both readers build the same maze from the game code; the guide sees
  the whole map (walls, landmarks, key, door), the explorer only the cells
  around them. The explorer describes, the guide leads; the explorer's
  reader counts the steps against the shortest way.
- Easy 7×7 (the explorer sees two cells around), Medium 9×9 and Hard 11×11
  (one cell around); pencil marks on the guide's map; auto-save.
