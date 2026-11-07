/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

//import 'dart:html';

import 'package:flauncher/providers/photo_wallpaper_source.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

//import '../mocks.mocks.dart';

void main() async {
  SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
  final sharedPreferences = await SharedPreferences.getInstance();
  final settingsService = SettingsService(sharedPreferences);

  setUp(() async {
    await sharedPreferences.clear();
  });

  test("watchNextBigPictureMode default and update", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    expect(settingsService.watchNextBigPictureMode, isFalse);

    await settingsService.setWatchNextBigPictureMode(true);
    expect(settingsService.watchNextBigPictureMode, isTrue);

    await settingsService.setWatchNextBigPictureMode(false);
    expect(settingsService.watchNextBigPictureMode, isFalse);
  });

  test("watchNextMaxItems default and update", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    expect(settingsService.watchNextMaxItems, equals(0));

    await settingsService.setWatchNextMaxItems(10);
    expect(settingsService.watchNextMaxItems, equals(10));

    await settingsService.setWatchNextMaxItems(0);
    expect(settingsService.watchNextMaxItems, equals(0));
  });

  test("watchNextExcludedPackages default and toggle", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    expect(settingsService.watchNextExcludedPackages, isEmpty);
    expect(settingsService.isWatchNextPackageExcluded("com.plexapp.android"), isFalse);

    await settingsService.toggleWatchNextExcludedPackage("com.plexapp.android");
    expect(settingsService.watchNextExcludedPackages, ["com.plexapp.android"]);
    expect(settingsService.isWatchNextPackageExcluded("com.plexapp.android"), isTrue);

    await settingsService.toggleWatchNextExcludedPackage("com.netflix.ninja");
    expect(settingsService.watchNextExcludedPackages, ["com.plexapp.android", "com.netflix.ninja"]);

    await settingsService.toggleWatchNextExcludedPackage("com.plexapp.android");
    expect(settingsService.watchNextExcludedPackages, ["com.netflix.ninja"]);
    expect(settingsService.isWatchNextPackageExcluded("com.plexapp.android"), isFalse);
  });


  test("setUse24HourTimeFormat", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final expected = "XYZ";

    await settingsService.setDateTimeFormat("", expected);

    expect(settingsService.timeFormat, expected);
  });

  test("setGradientUuid", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    await settingsService.setGradientUuid("4730aa2d-1a90-49a6-9942-ffe82f470e26");

    expect(sharedPreferences.getString("gradient_uuid"), "4730aa2d-1a90-49a6-9942-ffe82f470e26");
  });


  group("getGradientUuid", () {
    test("without uuid from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final settingsService = SettingsService(sharedPreferences);

      final gradientUuid = settingsService.gradientUuid;

      expect(gradientUuid, null);
    });

    test("with uuid from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      sharedPreferences.setString("gradient_uuid", "4730aa2d-1a90-49a6-9942-ffe82f470e26");
      final settingsService = SettingsService(sharedPreferences);

      final gradientUuid = settingsService.gradientUuid;

      expect(gradientUuid, "4730aa2d-1a90-49a6-9942-ffe82f470e26");
    });
  });

  group("getDateFormat", ()  {
    test("with default", () async {
      expect(settingsService.dateFormat, SettingsService.defaultDateFormat);
    });

    test("with value set", () async {
      final expected = "XYZ";

      settingsService.setDateTimeFormat(expected, "");

      expect(settingsService.dateFormat, expected);
    });
  });

  group("unsplash slideshow", () {
    test("stays disabled without an access key", () async {
      await settingsService.setUnsplashSlideshowEnabled(true);

      expect(settingsService.unsplashSlideshowEnabled, isFalse);
    });

    test("runs once a key is set, and clearing the key disables it", () async {
      await settingsService.setUnsplashAccessKey("  abc  ");
      await settingsService.setUnsplashSlideshowEnabled(true);

      expect(settingsService.unsplashAccessKey, "abc");
      expect(settingsService.unsplashSlideshowEnabled, isTrue);

      await settingsService.setUnsplashAccessKey("");
      await settingsService.setUnsplashAccessKey("abc");

      expect(settingsService.unsplashSlideshowEnabled, isFalse);
    });

    test("has defaults for interval and sources", () {
      expect(settingsService.unsplashIntervalMinutes, 10);
      expect(settingsService.unsplashDaySources, ['nature', 'wallpapers', '3d-renders']);
      expect(settingsService.unsplashNightSources, ['milkyway']);
    });
  });

  group("hideStatusBarInGrid", () {
    test("defaults to false", () {
      expect(settingsService.hideStatusBarInGrid, isFalse);
    });

    test("persists value", () async {
      await settingsService.setHideStatusBarInGrid(true);
      expect(settingsService.hideStatusBarInGrid, isTrue);
      expect(sharedPreferences.getBool("hide_status_bar_in_grid"), isTrue);

      await settingsService.setHideStatusBarInGrid(false);
      expect(settingsService.hideStatusBarInGrid, isFalse);
      expect(sharedPreferences.getBool("hide_status_bar_in_grid"), isFalse);
    });
  });

  group("watchNextHideProgramsWithoutImages", () {
    test("defaults to false", () {
      expect(settingsService.watchNextHideProgramsWithoutImages, isFalse);
    });

    test("persists value", () async {
      await settingsService.setWatchNextHideProgramsWithoutImages(true);
      expect(settingsService.watchNextHideProgramsWithoutImages, isTrue);
      expect(sharedPreferences.getBool("watch_next_hide_programs_without_images"), isTrue);

      await settingsService.setWatchNextHideProgramsWithoutImages(false);
      expect(settingsService.watchNextHideProgramsWithoutImages, isFalse);
      expect(sharedPreferences.getBool("watch_next_hide_programs_without_images"), isFalse);
    });
  });

  group("4K photos", () {
    test("defaults", () {
      expect(settingsService.photoWallpaperEnabled, isFalse);
      expect(settingsService.photoWallpaperSource, PhotoSource.spotlight);
      expect(settingsService.photoWallpaperIntervalMinutes, 60);
      expect(settingsService.photoWallpaperShowCredit, isTrue);
      expect(settingsService.photoWallpaperCredits, isEmpty);
      expect(settingsService.photoWallpaperSeen, isEmpty);
      expect(settingsService.photoScreensaverClock, isTrue);
    });

    test("the screensaver clock is stored where the Android screensaver reads it", () async {
      await settingsService.setPhotoScreensaverClock(false);

      expect(settingsService.photoScreensaverClock, isFalse);
      expect(sharedPreferences.getBool("photo_screensaver_clock"), isFalse);
    });

    test("setters persist and notify", () async {
      var notified = 0;
      void listener() => notified++;
      settingsService.addListener(listener);
      addTearDown(() => settingsService.removeListener(listener));

      await settingsService.setPhotoWallpaperSource(PhotoSource.bing);
      await settingsService.setPhotoWallpaperIntervalMinutes(360);
      await settingsService.setPhotoWallpaperShowCredit(false);

      expect(settingsService.photoWallpaperSource, PhotoSource.bing);
      expect(sharedPreferences.getString("photo_wallpaper_source"), "bing");
      expect(settingsService.photoWallpaperIntervalMinutes, 360);
      expect(settingsService.photoWallpaperShowCredit, isFalse);
      // Read under this name by the Android screensaver.
      expect(sharedPreferences.getBool("photo_wallpaper_show_credit"), isFalse);
      expect(notified, 3);
    });

    test("the photo on screen is remembered across restarts", () async {
      expect(settingsService.photoWallpaperCurrent, isNull);
      expect(settingsService.photoWallpaperCurrentSince, isNull);
      final since = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      await settingsService.setPhotoWallpaperCurrent('sp_1', since);

      expect(settingsService.photoWallpaperCurrent, 'sp_1');
      expect(settingsService.photoWallpaperCurrentSince, since);
    });

    test("4K photos and Unsplash exclude each other", () async {
      await settingsService.setUnsplashAccessKey("abc");
      await settingsService.setUnsplashSlideshowEnabled(true);
      await settingsService.setPhotoWallpaperEnabled(true);

      expect(settingsService.photoWallpaperEnabled, isTrue);
      expect(settingsService.unsplashSlideshowEnabled, isFalse);

      await settingsService.setUnsplashSlideshowEnabled(true);

      expect(settingsService.unsplashSlideshowEnabled, isTrue);
      expect(settingsService.photoWallpaperEnabled, isFalse);
    });

    test("credits survive a round trip and garbage reads as empty", () async {
      await settingsService.setPhotoWallpaperCredits({
        'sp_1': const PhotoCredit('Title', 'Place · © Someone'),
        'bing_X': const PhotoCredit('Other', 'Somewhere (© Agency)'),
      });

      expect(settingsService.photoWallpaperCredits, {
        'sp_1': const PhotoCredit('Title', 'Place · © Someone'),
        'bing_X': const PhotoCredit('Other', 'Somewhere (© Agency)'),
      });

      await sharedPreferences.setString("photo_wallpaper_credits", "{not json");
      expect(settingsService.photoWallpaperCredits, isEmpty);

      await sharedPreferences.setString("photo_wallpaper_credits", '{"a": 3, "b": {"title": "t", "copyright": "c"}}');
      expect(settingsService.photoWallpaperCredits, {'b': const PhotoCredit('t', 'c')});
    });

    test("seen ids are deduped and capped, oldest dropped", () async {
      await settingsService.addPhotoWallpaperSeen(['a', 'b']);
      await settingsService.addPhotoWallpaperSeen(['a']);
      expect(settingsService.photoWallpaperSeen, ['b', 'a']);

      await settingsService.addPhotoWallpaperSeen([for (var i = 0; i < 250; i++) 'id$i']);
      final seen = settingsService.photoWallpaperSeen;
      expect(seen, hasLength(SettingsService.photoWallpaperSeenMax));
      expect(seen.first, 'id50');
      expect(seen.last, 'id249');
    });
  });

  group("migrateLegacyPrefs", () {
    Future<void> setReddit({bool? enabled, int? interval}) async {
      if (enabled != null) await sharedPreferences.setBool('reddit_wallpaper_enabled', enabled);
      if (interval != null) await sharedPreferences.setInt('reddit_interval_minutes', interval);
      await sharedPreferences.setStringList('reddit_subreddits', ['x']);
      await sharedPreferences.setString('reddit_sort', 'hot');
      await sharedPreferences.setString('reddit_current_title', 't');
    }

    void expectNoLegacyKeys() {
      for (final key in SettingsService.legacyRedditKeys) {
        expect(sharedPreferences.containsKey(key), isFalse, reason: key);
      }
    }

    test("an enabled Reddit wallpaper becomes 4K photos with its interval", () async {
      await sharedPreferences.setBool('unsplash_slideshow_enabled', true);
      await setReddit(enabled: true, interval: 30);

      await SettingsService.migrateLegacyPrefs(sharedPreferences);

      expect(settingsService.photoWallpaperEnabled, isTrue);
      expect(settingsService.photoWallpaperIntervalMinutes, 30);
      expect(sharedPreferences.getBool('unsplash_slideshow_enabled'), isFalse);
      expectNoLegacyKeys();
    });

    test("a disabled Reddit wallpaper only removes the old prefs", () async {
      await setReddit(enabled: false, interval: 30);

      await SettingsService.migrateLegacyPrefs(sharedPreferences);

      expect(settingsService.photoWallpaperEnabled, isFalse);
      expect(sharedPreferences.containsKey('photo_wallpaper_interval_minutes'), isFalse);
      expectNoLegacyKeys();
    });

    test("an interval that is not a 4K photos choice keeps the default", () async {
      await setReddit(enabled: true, interval: 5);

      await SettingsService.migrateLegacyPrefs(sharedPreferences);

      expect(settingsService.photoWallpaperEnabled, isTrue);
      expect(settingsService.photoWallpaperIntervalMinutes, 60);
    });

    test("running twice changes nothing the second time", () async {
      await setReddit(enabled: true, interval: 30);
      await SettingsService.migrateLegacyPrefs(sharedPreferences);
      await settingsService.setPhotoWallpaperEnabled(false);
      final before = {for (final k in sharedPreferences.getKeys()) k: sharedPreferences.get(k)};

      await SettingsService.migrateLegacyPrefs(sharedPreferences);

      expect({for (final k in sharedPreferences.getKeys()) k: sharedPreferences.get(k)}, before);
      expect(settingsService.photoWallpaperEnabled, isFalse);
    });

    test("an explicit 4K photos choice wins over the Reddit pref", () async {
      await settingsService.setPhotoWallpaperEnabled(false);
      await setReddit(enabled: true);

      await SettingsService.migrateLegacyPrefs(sharedPreferences);

      expect(settingsService.photoWallpaperEnabled, isFalse);
      expectNoLegacyKeys();
    });
  });
}
