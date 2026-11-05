# Fork changelog

Changes in KarimHmaissi/arclauncher on top of upstream meddouribadis/arclauncher.

## 2026-11-05

- **Watch Next row stops vanishing and the dock stops jumping (polish A4).**
  Every refresh (each return to Home and every 5 minutes) used to hide the
  row while Watch Next was re-read, so the dock jumped by the row's height;
  a failed read emptied it. Now only the very first load hides it, a
  refresh that finds the same cards changes nothing on screen (engagement
  times alone don't count), and a failed read keeps the last good row.
