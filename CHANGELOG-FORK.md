# Fork changelog

Changes in KarimHmaissi/arclauncher on top of upstream meddouribadis/arclauncher.

## 2026-11-04

- Profile builds now use the debug app id (`com.omeda.arc.debug`) and debug signing,
  so the Shield can swap between the fast profile build and the hot-reload debug
  build without losing Arc's settings, dock or wallpaper.
## 2026-11-05

- **Watch Next row stops vanishing and the dock stops jumping (polish A4).**
  Every refresh (each return to Home and every 5 minutes) used to hide the
  row while Watch Next was re-read, so the dock jumped by the row's height;
  a failed read emptied it. Now only the very first load hides it, a
  refresh that finds the same cards changes nothing on screen (engagement
  times alone don't count), and a failed read keeps the last good row.
- **Watch Next cards show the episode, time left and a progress bar, with
  sharp art (polish A5 + A8).** Cards read "S3 · E7 · 22 min left" (or
  "· New" for an unstarted episode) instead of a generic "Watch Next"; the
  progress bar shows real progress (it was hard-coded to 0), and the hero's
  Resume / Watch follows it. Posters decode at the card's real pixel size
  instead of half size. Needs Plezy publishing 1280×720 art for full effect.
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
