# Fork changelog

Changes in KarimHmaissi/arclauncher on top of upstream meddouribadis/arclauncher.

## 2026-11-07

- **Screensavers wake instantly.** New "Arc Photos" screensaver (pick it in
  Android Settings › Device Preferences › Screen saver) shows the same 4K photos as the
  wallpaper, crossfading slowly every few minutes through every cached
  photo, with Arc's clock style and the photo credit. Any button or touch
  closes it at once: no fade-out, and the button press doesn't leak
  through to Home. Arc's clock screensaver closes the same instant way.
  While it is the chosen screensaver, Arc keeps its photos topped up even
  when the wallpaper is something else.
- **Home doesn't fade back in.** If the wallpaper changed while a
  screensaver or app was in front, Arc decodes the new one while away and
  shows it on the first frame back, instead of replaying the 1.5 s
  crossfade.
- **4K photos replace the Reddit wallpaper.** Reddit now refuses all
  unauthenticated requests, so the Reddit source and its settings are gone.
  Settings › Wallpaper › 4K photos shows 3840×2160 photos from Windows
  Spotlight ("Varied photos") or Bing ("Photo of the day"), picked for the
  device's language and region, with the other source as a fallback.
  Up to 24 photos are kept on disk (about 60-90 MB), topped up a few at a
  time every few hours; the wallpaper moves through them at its own
  interval, and a restart keeps the photo that was on screen. Offline, the
  cached photos stay; with nothing cached, your previous wallpaper (or the
  gradient) shows. If the Reddit wallpaper was on, 4K photos are switched
  on once in its place.

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

## 2026-11-04

- Profile builds now use the debug app id (`com.omeda.arc.debug`) and debug signing,
  so the Shield can swap between the fast profile build and the hot-reload debug
  build without losing Arc's settings, dock or wallpaper.
