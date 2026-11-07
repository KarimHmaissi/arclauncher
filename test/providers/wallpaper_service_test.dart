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

import 'dart:async';
import 'dart:io';

import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/photo_wallpaper_source.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../mocks.mocks.dart';

MockSettingsService _createSettingsService({
  bool timeBasedWallpaperEnabled = false,
  bool unsplashSlideshowEnabled = false,
  int unsplashIntervalMinutes = 10,
  bool photoWallpaperEnabled = false,
  int photoWallpaperIntervalMinutes = 60,
  PhotoSource photoWallpaperSource = PhotoSource.spotlight,
  bool photoWallpaperShowCredit = true,
  Map<String, PhotoCredit> photoWallpaperCredits = const {},
  List<String> photoWallpaperSeen = const [],
  String? photoWallpaperCurrent,
  DateTime? photoWallpaperCurrentSince,
}) {
  final s = MockSettingsService();
  when(s.timeBasedWallpaperEnabled).thenReturn(timeBasedWallpaperEnabled);
  when(s.unsplashSlideshowEnabled).thenReturn(unsplashSlideshowEnabled);
  when(s.unsplashIntervalMinutes).thenReturn(unsplashIntervalMinutes);
  when(s.photoWallpaperEnabled).thenReturn(photoWallpaperEnabled);
  when(s.photoWallpaperIntervalMinutes).thenReturn(photoWallpaperIntervalMinutes);
  when(s.photoWallpaperSource).thenReturn(photoWallpaperSource);
  when(s.photoWallpaperShowCredit).thenReturn(photoWallpaperShowCredit);
  when(s.photoWallpaperCredits).thenReturn(photoWallpaperCredits);
  when(s.photoWallpaperSeen).thenReturn(photoWallpaperSeen);
  when(s.photoWallpaperCurrent).thenReturn(photoWallpaperCurrent);
  when(s.photoWallpaperCurrentSince).thenReturn(photoWallpaperCurrentSince);
  return s;
}

/// Hands out queued photos instead of downloading them.
class _FakePhotoWallpaperSource extends PhotoWallpaperSource {
  _FakePhotoWallpaperSource(super.cacheDir)
    : super(client: MockClient((_) async => throw StateError('no network in tests')));

  /// Photos the next [fillPool] call "downloads".
  final List<PhotoWallpaper> queue = [];
  int fills = 0;

  /// When set, a fill pauses after its first photo until this completes.
  Completer<void>? holdAfterFirst;

  @override
  Future<List<PhotoWallpaper>> fillPool({
    required PhotoSource source,
    required Set<String> seen,
    Set<String> Function()? protect,
    Future<void> Function(PhotoWallpaper photo)? onSaved,
  }) async {
    fills++;
    final batch = [...queue];
    queue.clear();
    final saved = <PhotoWallpaper>[];
    for (final p in batch) {
      cacheDir.createSync(recursive: true);
      File("${cacheDir.path}/${p.id}.jpg").writeAsBytesSync([0xFF, 0xD8]);
      saved.add(p);
      await onSaved?.call(p);
      final hold = holdAfterFirst;
      if (saved.length == 1 && hold != null) await hold.future;
    }
    return saved;
  }
}

/// Writes fake cached photos, the first one oldest.
void _seedPhotos(Directory dir, List<String> ids) {
  dir.createSync(recursive: true);
  final base = DateTime.now().subtract(const Duration(minutes: 30));
  for (var i = 0; i < ids.length; i++) {
    File("${dir.path}/${ids[i]}.jpg")
      ..writeAsBytesSync([0xFF, 0xD8])
      ..setLastModifiedSync(base.add(Duration(minutes: i)));
  }
}

Future<void> _eventually(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

void main() {
  late final _MockPathProviderPlatform pathProviderPlatform;
  setUpAll(() {
    pathProviderPlatform = _MockPathProviderPlatform();
    when(pathProviderPlatform.getApplicationDocumentsPath()).thenAnswer((_) => Future.value("."));
    PathProviderPlatform.instance = pathProviderPlatform;
  });

  test("pickWallpaper saves source file", () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final settingsService = _createSettingsService();
    final wallpaperService = WallpaperService(settingsService);
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

    final source = File("test_wallpaper_src");
    await source.writeAsBytes([0x01, 0x02]);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
      final dest = File("./wallpaper");
      if (await dest.exists()) await dest.delete();
    });

    await wallpaperService.pickWallpaper(source);

    expect(await File("./wallpaper").exists(), isTrue);
    expect(await File("./wallpaper").readAsBytes(), [0x01, 0x02]);
  });

  test("pickWallpaperFromUri saves the selected image bytes", () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('me.efesser.flauncher/method');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'loadContentUriImage') {
        return Uint8List.fromList([0x03, 0x04]);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final settingsService = _createSettingsService();
    final wallpaperService = WallpaperService(settingsService);
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
    addTearDown(() async {
      final dest = File('./wallpaper');
      if (await dest.exists()) await dest.delete();
    });

    await wallpaperService.pickWallpaperFromUri('content://media/external/images/media/1');

    expect(await File('./wallpaper').readAsBytes(), [0x03, 0x04]);
  });

  test("setGradient", () async {
    final settingsService = _createSettingsService();
    final wallpaperService = WallpaperService(settingsService);

    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
    await wallpaperService.setGradient(FLauncherGradients.greatWhale);

    verify(settingsService.setGradientUuid(FLauncherGradients.greatWhale.uuid));
    expect(wallpaperService.wallpaper, null);
  });

  group("getGradient", () {
    test("without uuid from settings", () async {
      final settingsService = _createSettingsService();
      final wallpaperService = WallpaperService(settingsService);
      when(settingsService.gradientUuid).thenReturn(null);

      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
      final gradient = wallpaperService.gradient;

      expect(gradient, FLauncherGradients.saintPetersburg);
    });

    test("with uuid from settings", () async {
      final settingsService = _createSettingsService();
      final wallpaperService = WallpaperService(settingsService);
      when(settingsService.gradientUuid).thenReturn(FLauncherGradients.grassShampoo.uuid);
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      final gradient = wallpaperService.gradient;

      expect(gradient, FLauncherGradients.grassShampoo);
    });
  });

  group("4K photos", () {
    late Directory docs;
    late Directory photoDir;
    _FakePhotoWallpaperSource? fake;
    WallpaperService? service;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('wallpaper_service_test');
      photoDir = Directory("${docs.path}/photo_wallpaper");
      when(pathProviderPlatform.getApplicationDocumentsPath()).thenAnswer((_) async => docs.path);
      fake = null;
      service = null;
    });

    tearDown(() {
      service?.dispose();
      when(pathProviderPlatform.getApplicationDocumentsPath()).thenAnswer((_) => Future.value("."));
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    Future<WallpaperService> start(
      MockSettingsService settings, {
      bool screensaverInUse = false,
      void Function(_FakePhotoWallpaperSource)? setUpSource,
    }) async {
      final s = WallpaperService(
        settings,
        photoSourceFactory: (dir) {
          final f = fake = _FakePhotoWallpaperSource(dir);
          setUpSource?.call(f);
          return f;
        },
        photoScreensaverInUse: () async => screensaverInUse,
        photoConfigDebounce: const Duration(milliseconds: 1),
      );
      service = s;
      await _eventually(() => s.isInitialized);
      // Let the first advance / fill settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return s;
    }

    String? shownId(WallpaperService s) {
      final w = s.wallpaper;
      return w is FileImage ? PhotoWallpaperSource.idOf(w.file) : null;
    }

    test("credit is null when disabled", () async {
      _seedPhotos(photoDir, ['sp_1']);
      final s = await start(_createSettingsService(photoWallpaperCredits: {'sp_1': const PhotoCredit('T', 'C')}));

      expect(s.photoWallpaperCredit, isNull);
    });

    test("credit is null when the credit is switched off", () async {
      _seedPhotos(photoDir, ['sp_1']);
      final s = await start(
        _createSettingsService(
          photoWallpaperEnabled: true,
          photoWallpaperShowCredit: false,
          photoWallpaperCredits: {'sp_1': const PhotoCredit('T', 'C')},
        ),
      );

      expect(s.photoWallpaperCredit, isNull);
    });

    test("shows the newest cached photo with its credit", () async {
      _seedPhotos(photoDir, ['sp_0', 'sp_1']);
      final s = await start(
        _createSettingsService(
          photoWallpaperEnabled: true,
          photoWallpaperCredits: {'sp_1': const PhotoCredit('T', 'C')},
        ),
      );

      expect(s.wallpaper, isA<FileImage>());
      expect((s.wallpaper as FileImage).file.path, "${photoDir.path}/sp_1.jpg");
      expect(s.photoWallpaperCredit, const PhotoCredit('T', 'C'));
    });

    test("an empty cache with no network falls back to the gradient without throwing", () async {
      final s = await start(_createSettingsService(photoWallpaperEnabled: true));

      expect(fake!.fills, greaterThan(0));
      expect(s.wallpaper, isNull);
      expect(s.photoWallpaperCredit, isNull);
    });

    test("downloaded photos are shown and their credits written, for photos on disk only", () async {
      final settings = _createSettingsService(
        photoWallpaperEnabled: true,
        photoWallpaperCredits: {'gone': const PhotoCredit('Old', 'Gone')},
      );
      final s = WallpaperService(
        settings,
        photoSourceFactory: (dir) => fake = _FakePhotoWallpaperSource(dir)
          ..queue.add(
            const PhotoWallpaper(
              'sp_new',
              'https://example.invalid/x.jpg',
              PhotoCredit('New', 'Here'),
              PhotoSource.spotlight,
            ),
          ),
      );
      service = s;
      await _eventually(() => shownId(s) == 'sp_new');

      final written = verify(settings.setPhotoWallpaperCredits(captureAny)).captured.last as Map<String, PhotoCredit>;
      expect(written, {'sp_new': const PhotoCredit('New', 'Here')});
      verify(settings.addPhotoWallpaperSeen(['sp_new']));
    });

    test("advancing walks the pool: newest unshown first, then round robin, never the same twice", () async {
      _seedPhotos(photoDir, ['sp_a', 'sp_b', 'sp_c']); // sp_c newest
      final s = await start(_createSettingsService(photoWallpaperEnabled: true));
      expect(shownId(s), 'sp_c');

      final shown = <String?>[];
      for (var i = 0; i < 5; i++) {
        await s.advancePhotoWallpaper();
        shown.add(shownId(s));
      }

      expect(shown, ['sp_b', 'sp_a', 'sp_c', 'sp_b', 'sp_a']);
    });

    test("the chosen source's photos come first", () async {
      _seedPhotos(photoDir, ['bing_X', 'sp_a', 'sp_b']);
      final s = await start(
        _createSettingsService(photoWallpaperEnabled: true, photoWallpaperSource: PhotoSource.bing),
      );

      await s.advancePhotoWallpaper();

      expect(shownId(s), 'bing_X');
    });

    test("with no other photo, advancing downloads more first", () async {
      _seedPhotos(photoDir, ['sp_a']);
      final s = await start(_createSettingsService(photoWallpaperEnabled: true));
      expect(shownId(s), 'sp_a');
      fake!.queue.add(
        const PhotoWallpaper('sp_b', 'https://example.invalid/b.jpg', PhotoCredit('B', 'b'), PhotoSource.spotlight),
      );

      await s.advancePhotoWallpaper();

      expect(shownId(s), 'sp_b');
    });

    PhotoWallpaper photo(String id) =>
        PhotoWallpaper(id, 'https://example.invalid/$id.jpg', PhotoCredit(id, '© $id'), PhotoSource.spotlight);

    test("the first new photo shows as soon as it lands, while the rest keep downloading", () async {
      final hold = Completer<void>();
      final s = await start(
        _createSettingsService(photoWallpaperEnabled: true),
        setUpSource: (f) => f
          ..queue.addAll([photo('sp_1'), photo('sp_2')])
          ..holdAfterFirst = hold,
      );

      await _eventually(() => shownId(s) == 'sp_1');
      expect(File("${photoDir.path}/sp_2.jpg").existsSync(), isFalse);
      hold.complete();
    });

    test("an unforced top-up runs at most once per refresh period", () async {
      _seedPhotos(photoDir, ['bing_X', 'sp_a']); // sp_a on screen; no other Spotlight photo
      final s = await start(_createSettingsService(photoWallpaperEnabled: true));
      expect(shownId(s), 'sp_a');
      expect(fake!.fills, 1); // The pool isn't full: topped up at start.

      final shown = <String?>[];
      for (var i = 0; i < 3; i++) {
        await s.advancePhotoWallpaper();
        shown.add(shownId(s));
      }

      // No other Spotlight photo twice, but the Bing one could be shown: no new download.
      expect(shown, ['bing_X', 'sp_a', 'bing_X']);
      expect(fake!.fills, 1);
    });

    test("with nothing else to show, every advance tries a top-up", () async {
      final s = await start(_createSettingsService(photoWallpaperEnabled: true));
      expect(fake!.fills, 1);

      await s.advancePhotoWallpaper();

      expect(fake!.fills, 2);
    });

    test("a top-up 3 hours after the last one is due even if the timer runs a little early", () {
      final last = DateTime(2026, 1, 1, 12);
      expect(WallpaperService.photoFillDue(null, last), isTrue);
      expect(WallpaperService.photoFillDue(last, last.add(const Duration(hours: 1))), isFalse);
      expect(WallpaperService.photoFillDue(last, last.add(const Duration(hours: 3, seconds: -1))), isTrue);
    });

    test("changing the source shows its photo and tops up at once, even within the refresh period", () async {
      _seedPhotos(photoDir, ['bing_X', 'sp_a']);
      final settings = _createSettingsService(photoWallpaperEnabled: true);
      final s = await start(settings);
      expect(shownId(s), 'sp_a');
      expect(fake!.fills, 1);

      when(settings.photoWallpaperSource).thenReturn(PhotoSource.bing);
      final listener = verify(settings.addListener(captureAny)).captured.single as VoidCallback;
      listener();

      await _eventually(() => shownId(s) == 'bing_X');
      expect(fake!.fills, 2);
    });

    test("a restart shows the photo that was on screen, not the newest download", () async {
      _seedPhotos(photoDir, ['sp_a', 'sp_b']); // sp_b newest
      final settings = _createSettingsService(
        photoWallpaperEnabled: true,
        photoWallpaperCurrent: 'sp_a',
        photoWallpaperCurrentSince: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final s = await start(settings);

      expect(shownId(s), 'sp_a');
      verifyNever(settings.setPhotoWallpaperCurrent(any, any));
    });

    test(
      "a restart changes the photo when it has been on screen for the interval, and remembers the new one",
      () async {
        _seedPhotos(photoDir, ['sp_a', 'sp_b']); // both downloaded under an hour ago
        final settings = _createSettingsService(
          photoWallpaperEnabled: true,
          photoWallpaperCurrent: 'sp_a',
          photoWallpaperCurrentSince: DateTime.now().subtract(const Duration(hours: 2)),
        );
        final s = await start(settings);

        expect(shownId(s), 'sp_b');
        verify(settings.setPhotoWallpaperCurrent('sp_b', any)).called(1);
      },
    );

    test("with 4K photos off, the pool is still topped up while Arc Photos is the screensaver", () async {
      final settings = _createSettingsService();
      final s = await start(settings, screensaverInUse: true, setUpSource: (f) => f.queue.add(photo('sp_1')));

      expect(fake!.fills, 1);
      expect(File("${photoDir.path}/sp_1.jpg").existsSync(), isTrue);
      verify(settings.addPhotoWallpaperSeen(['sp_1']));
      expect(s.wallpaper, isNull); // Not the wallpaper: only for the screensaver.
    });

    test("with 4K photos off and Arc Photos not in use, nothing is downloaded", () async {
      await start(_createSettingsService(), setUpSource: (f) => f.queue.add(photo('sp_1')));

      expect(fake!.fills, 0);
    });

    test("pickVideoWallpaper turns 4K photos off", () async {
      final settings = _createSettingsService(photoWallpaperEnabled: true);
      final s = await start(settings);
      final video = File("${docs.path}/test_video.mp4")..writeAsBytesSync([0x01]);

      await s.pickVideoWallpaper(video);

      verify(settings.setPhotoWallpaperEnabled(false)).called(1);
    });

    test("setGradient turns 4K photos off", () async {
      final settings = _createSettingsService(photoWallpaperEnabled: true);
      final s = await start(settings);

      await s.setGradient(FLauncherGradients.greatWhale);

      verify(settings.setPhotoWallpaperEnabled(false)).called(1);
    });

    test("the old Reddit cache folder is deleted", () async {
      final legacy = Directory("${docs.path}/reddit_slideshow")..createSync();
      File("${legacy.path}/old.jpg").writeAsBytesSync([1]);

      await start(_createSettingsService());

      await _eventually(() => !legacy.existsSync());
    });
  });
}

class _MockPathProviderPlatform extends Mock with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() =>
      super.noSuchMethod(Invocation.method(#getApplicationDocumentsPath, []), returnValue: Future<String?>.value());
}
