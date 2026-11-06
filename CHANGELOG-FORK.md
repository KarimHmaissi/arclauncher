# Fork changelog

Changes in KarimHmaissi/arclauncher on top of upstream meddouribadis/arclauncher.

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
