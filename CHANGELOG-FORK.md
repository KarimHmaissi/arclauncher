# Fork changelog

Changes in KarimHmaissi/arclauncher on top of upstream meddouribadis/arclauncher.

## 2026-11-05

- **Home lands on tonight's episode (polish A10).** Coming back to Arc after
  more than 30 seconds away, pressing Home while Arc is already in front, or
  Back at the root (with the default Back action) scrolls Home to the top and
  focuses the first Watch Next card; with no Watch Next cards the dock's
  first app gets focus. Cards keep focus by identity, so a reorder no longer
  moves focus to a different show. New setting: Watch Next → "Start on
  Continue Watching" (on by default).
- **Watch Next is read again 3 s after Arc returns** (polish A6), so the next
  episode Plezy publishes as an episode ends shows up without waiting for
  the 5-minute refresh.
