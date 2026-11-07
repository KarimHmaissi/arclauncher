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

import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/photo_wallpaper_source.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/unsplash_slideshow.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperService extends ChangeNotifier {
  final SettingsService _settingsService;
  final FLauncherChannel _channel = FLauncherChannel();

  late File _wallpaperFile;
  late File _wallpaperDayFile;
  late File _wallpaperNightFile;
  late File _wallpaperVideoFile;
  late File _wallpaperDayVideoFile;
  late File _wallpaperNightVideoFile;
  bool _initialized = false;
  Timer? _timer;
  int _wallpaperRevision = 0;

  late UnsplashSlideshow _slideshow;
  Timer? _slideshowTimer;
  final Random _random = Random();
  File? _slideshowFile;

  final PhotoWallpaperSource Function(Directory) _photoSourceFactory;
  late PhotoWallpaperSource _photoSource;
  Timer? _photoTimer;
  Timer? _photoDebounce;
  Timer? _photoRetry;
  Timer? _photoFillTimer;
  File? _photoFile;

  /// When [_photoFile] went on screen, if known.
  DateTime? _photoShownAt;

  /// Photo ids shown as the home wallpaper this session, least recent first.
  final List<String> _photoShown = [];
  static const int photoShownMax = 200;

  /// When the pool was last topped up, to keep downloads slow and polite.
  DateTime? _lastPhotoFill;

  /// The top-up running now, if any.
  Future<void>? _photoFilling;

  /// Completed when a photo lands while [advancePhotoWallpaper] waits for one.
  Completer<void>? _photoArrival;

  final Future<bool> Function()? _photoScreensaverInUse;
  final DateTime Function() _now;
  final Duration _photoConfigDebounce;

  /// The source the home wallpaper was last set up for.
  PhotoSource? _photoSourceShown;

  static const Duration photoConfigDebounce = Duration(seconds: 3);

  /// After a failed fetch (offline, both sources down), try again this soon
  /// instead of waiting for the next interval.
  static const Duration photoRetryDelay = Duration(minutes: 5);

  /// How often the photo pool is topped up with new photos, independent of the
  /// wallpaper interval. Also keeps the Arc Photos screensaver fresh.
  static const Duration photoPoolRefresh = Duration(hours: 3);

  /// A periodic top-up may fire a little under [photoPoolRefresh] after the
  /// last one (timer drift, or a fill started just after the timer); it still counts.
  static const Duration photoPoolRefreshSlack = Duration(minutes: 5);

  /// Whether the pool is due for a top-up, given when it was [last] topped up.
  @visibleForTesting
  static bool photoFillDue(DateTime? last, DateTime now) =>
      last == null || now.difference(last) >= photoPoolRefresh - photoPoolRefreshSlack;

  /// Credit to display while a 4K photo is on screen.
  PhotoCredit? get photoWallpaperCredit {
    final f = _photoFile;
    if (!_settingsService.photoWallpaperEnabled || !_settingsService.photoWallpaperShowCredit || f == null) {
      return null;
    }
    return _settingsService.photoWallpaperCredits[PhotoWallpaperSource.idOf(f)];
  }

  /// Photographer credit to display while the Unsplash slideshow is on screen.
  String? get slideshowAuthor =>
      _settingsService.unsplashSlideshowEnabled && _slideshowFile != null ? _settingsService.unsplashAuthor : null;

  ImageProvider? _wallpaper;
  int get wallpaperRevision => _wallpaperRevision;

  ImageProvider? get wallpaper => _wallpaper;

  File? get wallpaperVideoFile {
    final f = _resolveActiveVideoFile();
    return f != null && f.existsSync() ? f : null;
  }

  FLauncherGradient get gradient => FLauncherGradients.all.firstWhere(
    (gradient) => gradient.uuid == _settingsService.gradientUuid,
    orElse: () => FLauncherGradients.saintPetersburg,
  );

  WallpaperService(
    this._settingsService, {
    PhotoWallpaperSource Function(Directory)? photoSourceFactory,
    Future<bool> Function()? photoScreensaverInUse,
    DateTime Function()? now,
    Duration photoConfigDebounce = WallpaperService.photoConfigDebounce,
  }) : _photoSourceFactory = photoSourceFactory ?? PhotoWallpaperSource.new,
       _photoScreensaverInUse = photoScreensaverInUse,
       _now = now ?? DateTime.now,
       _photoConfigDebounce = photoConfigDebounce,
       _wallpaper = null {
    _settingsService.addListener(_onSettingsChanged);
    _init();
  }

  bool _lastTimeBasedEnabled = false;
  // Slideshow settings that require restarting its timer when they change.
  (bool, int) _lastSlideshowConfig = (false, 0);
  (bool, int) get _slideshowConfig =>
      (_settingsService.unsplashSlideshowEnabled, _settingsService.unsplashIntervalMinutes);

  (bool, int, PhotoSource) _lastPhotoConfig = (false, 0, PhotoSource.spotlight);
  (bool, int, PhotoSource) get _photoConfig => (
    _settingsService.photoWallpaperEnabled,
    _settingsService.photoWallpaperIntervalMinutes,
    _settingsService.photoWallpaperSource,
  );

  void _onSettingsChanged() {
    final enabled = _settingsService.timeBasedWallpaperEnabled;
    if (enabled != _lastTimeBasedEnabled) {
      _lastTimeBasedEnabled = enabled;
      _updateTimerState();
      _updateWallpaper();
    }
    if (_initialized && _slideshowConfig != _lastSlideshowConfig) {
      _lastSlideshowConfig = _slideshowConfig;
      _updateSlideshowState();
      _updateWallpaper(force: true);
    }
    if (_initialized && _photoConfig != _lastPhotoConfig) {
      _lastPhotoConfig = _photoConfig;
      // Debounce while enabled so cycling through the interval or source
      // choices triggers a single fetch instead of one per change.
      _photoDebounce?.cancel();
      if (_settingsService.photoWallpaperEnabled) {
        _photoDebounce = Timer(_photoConfigDebounce, _updatePhotoState);
      } else {
        _updatePhotoState();
      }
      _updateWallpaper(force: true);
    }
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    _timer?.cancel();
    _slideshowTimer?.cancel();
    _photoTimer?.cancel();
    _photoDebounce?.cancel();
    _photoRetry?.cancel();
    _photoFillTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final directory = await getApplicationDocumentsDirectory();
    _wallpaperFile = File("${directory.path}/wallpaper");
    _wallpaperDayFile = File("${directory.path}/wallpaper_day");
    _wallpaperNightFile = File("${directory.path}/wallpaper_night");
    _wallpaperVideoFile = File("${directory.path}/wallpaper_video");
    _wallpaperDayVideoFile = File("${directory.path}/wallpaper_day_video");
    _wallpaperNightVideoFile = File("${directory.path}/wallpaper_night_video");
    _slideshow = UnsplashSlideshow(Directory("${directory.path}/slideshow"));
    _slideshowFile = newestCachedImage(_slideshow.cacheDir);
    _photoSource = _photoSourceFactory(Directory("${directory.path}/photo_wallpaper"));
    _restorePhoto();
    unawaited(_deleteLegacyRedditCache(directory));
    _initialized = true;

    _lastTimeBasedEnabled = _settingsService.timeBasedWallpaperEnabled;
    _lastSlideshowConfig = _slideshowConfig;
    _lastPhotoConfig = _photoConfig;
    _updateWallpaper();
    _updateTimerState();
    _updateSlideshowState();
    // Topped up whether or not the photos are the wallpaper: the Arc Photos
    // screensaver shows them too.
    _photoFillTimer = Timer.periodic(photoPoolRefresh, (_) => _fillPhotoPool());
    _updatePhotoState();
  }

  /// After a restart, the photo that was on screen (else the newest one).
  void _restorePhoto() {
    final id = _settingsService.photoWallpaperCurrent;
    final saved = id == null ? null : File("${_photoSource.cacheDir.path}/$id.jpg");
    if (saved != null && saved.existsSync()) {
      _photoFile = saved;
      _photoShownAt = _settingsService.photoWallpaperCurrentSince;
    } else {
      _photoFile = newestCachedImage(_photoSource.cacheDir);
    }
    if (_photoFile != null) _photoShown.add(PhotoWallpaperSource.idOf(_photoFile!));
  }

  /// The Reddit wallpaper was removed; its cached images are dead weight.
  Future<void> _deleteLegacyRedditCache(Directory directory) async {
    try {
      final legacy = Directory("${directory.path}/reddit_slideshow");
      if (await legacy.exists()) await legacy.delete(recursive: true);
    } catch (_) {
      // Best effort only.
    }
  }

  void _updateSlideshowState() {
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
    if (!_settingsService.unsplashSlideshowEnabled) return;
    final interval = Duration(minutes: _settingsService.unsplashIntervalMinutes);
    _slideshowTimer = Timer.periodic(interval, (_) => _advanceSlideshow());
    final file = _slideshowFile;
    // Reuse the cached image after a reboot unless it is already due for a change.
    if (file == null || DateTime.now().difference(file.lastModifiedSync()) >= interval) {
      _advanceSlideshow();
    }
  }

  Future<void> _advanceSlideshow() async {
    final hour = DateTime.now().hour;
    // Same 6h-18h day/night split as the time-based wallpaper.
    final isDay = hour >= 6 && hour < 18;
    final result = await _slideshow.next(
      isDay
          ? pickSlideshowFilter(_settingsService.unsplashDaySources, defaultDaySlideshowSources, _random)
          : pickSlideshowFilter(_settingsService.unsplashNightSources, defaultNightSlideshowSources, _random),
      _settingsService.unsplashAccessKey,
    );
    if (result == null || !_settingsService.unsplashSlideshowEnabled) return;
    final (file, author) = result;
    _slideshowFile = file;
    await _settingsService.setUnsplashAuthor(author);
    _updateWallpaper(force: true);
  }

  void _updatePhotoState() {
    _photoTimer?.cancel();
    _photoTimer = null;
    _photoRetry?.cancel();
    _photoRetry = null;
    if (!_settingsService.photoWallpaperEnabled) {
      // Still fill an incomplete pool if the Arc Photos screensaver uses it.
      if (_photoSource.cachedPhotos().length < _photoSource.poolSize) _fillPhotoPool();
      return;
    }
    final source = _settingsService.photoWallpaperSource;
    final sourceChanged = _photoSourceShown != null && _photoSourceShown != source;
    _photoSourceShown = source;
    final interval = Duration(minutes: _settingsService.photoWallpaperIntervalMinutes);
    _photoTimer = Timer.periodic(interval, (_) => advancePhotoWallpaper());
    if (sourceChanged) {
      // A new source should get its own photos now, not at the next top-up.
      _lastPhotoFill = null;
      _fillPhotoPool();
    }
    final file = _photoFile;
    final onDisk = file != null && file.existsSync();
    final shownAt = _photoShownAt ?? (onDisk ? file.lastModifiedSync() : null);
    // Reuse the cached photo after a reboot unless it is already due for a change.
    if (sourceChanged || !onDisk || shownAt == null || _now().difference(shownAt) >= interval) {
      advancePhotoWallpaper();
    } else if (_photoSource.cachedPhotos().length < _photoSource.poolSize) {
      _fillPhotoPool();
    }
  }

  /// Downloads new photos into the pool and records their credits, while the
  /// photos are the wallpaper or the Arc Photos screensaver is in use. Runs at
  /// most once per [photoPoolRefresh] unless [force]d (nothing else to show);
  /// a call made while one runs gets that one.
  Future<void> _fillPhotoPool({bool force = false}) {
    final running = _photoFilling;
    if (running != null) return running;
    if (!force && !photoFillDue(_lastPhotoFill, _now())) return Future.value();
    final fill = _runPhotoFill().whenComplete(() => _photoFilling = null);
    _photoFilling = fill;
    return fill;
  }

  Future<void> _runPhotoFill() async {
    try {
      if (!_settingsService.photoWallpaperEnabled && !await _isPhotoScreensaverInUse()) return;
      _lastPhotoFill = _now();
      final saved = await _photoSource.fillPool(
        source: _settingsService.photoWallpaperSource,
        seen: _settingsService.photoWallpaperSeen.toSet(),
        // Asked at each prune: a photo shown while the fill runs is kept too.
        protect: () => {if (_photoFile != null) PhotoWallpaperSource.idOf(_photoFile!)},
        onSaved: _onPhotoSaved,
      );
      // Keep credits for the photos still on disk only (the pool was just pruned).
      final onDisk = _photoSource.cachedPhotos().map(PhotoWallpaperSource.idOf).toSet();
      final credits = {..._settingsService.photoWallpaperCredits, for (final p in saved) p.id: p.credit}
        ..removeWhere((id, _) => !onDisk.contains(id));
      await _settingsService.setPhotoWallpaperCredits(credits);
    } catch (e) {
      debugPrint("Photo wallpaper: $e");
    }
  }

  Future<bool> _isPhotoScreensaverInUse() => (_photoScreensaverInUse ?? _channel.isPhotoScreensaverInUse)();

  /// Records each photo as it lands, so it can be shown (with its credit) at once.
  Future<void> _onPhotoSaved(PhotoWallpaper photo) async {
    await _settingsService.addPhotoWallpaperSeen([photo.id]);
    await _settingsService.setPhotoWallpaperCredits({
      ..._settingsService.photoWallpaperCredits,
      photo.id: photo.credit,
    });
    final waiting = _photoArrival;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  /// The next pool photo for the home wallpaper: one from the chosen source if
  /// there is one, else any other photo in the pool ([preferredOnly] false).
  File? _pickPhoto({required bool preferredOnly}) {
    final current = _photoFile;
    final currentId = current == null ? null : PhotoWallpaperSource.idOf(current);
    final cached = _photoSource.cachedPhotos();
    final prefix = _settingsService.photoWallpaperSource.idPrefix;
    final preferred = PhotoWallpaperSource.pickNext(
      cached.where((f) => PhotoWallpaperSource.idOf(f).startsWith(prefix)).toList(),
      currentId: currentId,
      shownOrder: _photoShown,
    );
    if (preferred != null || preferredOnly) return preferred;
    return PhotoWallpaperSource.pickNext(cached, currentId: currentId, shownOrder: _photoShown);
  }

  /// Shows the next 4K photo from the pool ("Change photo now" and the timer),
  /// downloading more first when the pool has no other photo of the chosen
  /// source. Shows the first new photo as soon as it lands, while the rest of
  /// the top-up keeps downloading.
  Future<void> advancePhotoWallpaper() async {
    var next = _pickPhoto(preferredOnly: true);
    if (next == null) {
      final arrival = _photoArrival = Completer<void>();
      // Skip the top-up limit only when there is nothing else to show.
      final fill = _fillPhotoPool(force: _pickPhoto(preferredOnly: false) == null);
      await Future.any([fill, arrival.future]);
      if (identical(_photoArrival, arrival)) _photoArrival = null;
      next = _pickPhoto(preferredOnly: false);
    }
    if (!_settingsService.photoWallpaperEnabled) return;
    if (next == null) {
      // Offline or both sources down with nothing else cached: keep the cached
      // photo (or the next wallpaper in line), and try again soon.
      if (_settingsService.photoWallpaperIntervalMinutes > photoRetryDelay.inMinutes) {
        _photoRetry?.cancel();
        _photoRetry = Timer(photoRetryDelay, advancePhotoWallpaper);
      }
      return;
    }
    _photoRetry?.cancel();
    _photoFile = next;
    final shownAt = _photoShownAt = _now();
    final id = PhotoWallpaperSource.idOf(next);
    _photoShown
      ..remove(id)
      ..add(id);
    if (_photoShown.length > photoShownMax) _photoShown.removeAt(0);
    unawaited(_settingsService.setPhotoWallpaperCurrent(id, shownAt));
    _updateWallpaper(force: true);
  }

  void _updateTimerState() {
    final enabled = _settingsService.timeBasedWallpaperEnabled;
    if (enabled && (_timer == null || !_timer!.isActive)) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _updateWallpaper());
    } else if (!enabled && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  File? _resolveActiveVideoFile() {
    if (!isInitialized) return null;
    if (_settingsService.photoWallpaperEnabled) return null;
    if (_settingsService.unsplashSlideshowEnabled) return null;

    final now = DateTime.now();
    final isDay = now.hour >= 6 && now.hour < 18;
    final enabled = _settingsService.timeBasedWallpaperEnabled;

    if (enabled) {
      if (isDay && _wallpaperDayVideoFile.existsSync()) {
        return _wallpaperDayVideoFile;
      }
      if (!isDay && _wallpaperNightVideoFile.existsSync()) {
        return _wallpaperNightVideoFile;
      }
      if (_wallpaperVideoFile.existsSync()) {
        return _wallpaperVideoFile;
      }
    } else if (_wallpaperVideoFile.existsSync()) {
      return _wallpaperVideoFile;
    }
    return null;
  }

  bool get isInitialized => _initialized;

  void _updateWallpaper({bool force = false}) {
    final now = DateTime.now();
    final isDay = now.hour >= 6 && now.hour < 18;
    final enabled = _settingsService.timeBasedWallpaperEnabled;

    final videoFile = _resolveActiveVideoFile();

    ImageProvider? newWallpaper;

    final slideshowFile = _slideshowFile;
    final photoFile = _photoFile;
    if (_settingsService.photoWallpaperEnabled && photoFile != null && photoFile.existsSync()) {
      newWallpaper = FileImage(photoFile);
    } else if (_settingsService.unsplashSlideshowEnabled && slideshowFile != null && slideshowFile.existsSync()) {
      newWallpaper = FileImage(slideshowFile);
    } else if (videoFile != null) {
      newWallpaper = null;
    } else if (enabled) {
      if (isDay && _wallpaperDayFile.existsSync()) {
        newWallpaper = FileImage(_wallpaperDayFile);
      } else if (!isDay && _wallpaperNightFile.existsSync()) {
        newWallpaper = FileImage(_wallpaperNightFile);
      } else if (_wallpaperFile.existsSync()) {
        newWallpaper = FileImage(_wallpaperFile); // Fallback
      }
    } else if (_wallpaperFile.existsSync()) {
      newWallpaper = FileImage(_wallpaperFile);
    }

    if (_wallpaper != newWallpaper || videoFile != null || force) {
      _wallpaper = newWallpaper;
      _wallpaperRevision++;
      notifyListeners();
    }
  }

  Future<void> pickWallpaper(File sourceFile) async {
    await _saveImage(sourceFile, _wallpaperFile);
  }

  Future<void> pickWallpaperFromUri(String sourceUri) async {
    if (sourceUri.startsWith('file://')) {
      final file = File(Uri.parse(sourceUri).toFilePath());
      if (await file.exists()) {
        await pickWallpaper(file);
        return;
      }
    }
    await _saveImageBytes(await _channel.loadContentUriImage(sourceUri), _wallpaperFile);
  }

  Future<void> pickWallpaperDay(File sourceFile) async {
    await _saveImage(sourceFile, _wallpaperDayFile);
  }

  Future<void> pickWallpaperDayFromUri(String sourceUri) async {
    if (sourceUri.startsWith('file://')) {
      final file = File(Uri.parse(sourceUri).toFilePath());
      if (await file.exists()) {
        await pickWallpaperDay(file);
        return;
      }
    }
    await _saveImageBytes(await _channel.loadContentUriImage(sourceUri), _wallpaperDayFile);
  }

  Future<void> pickWallpaperNight(File sourceFile) async {
    await _saveImage(sourceFile, _wallpaperNightFile);
  }

  Future<void> pickWallpaperNightFromUri(String sourceUri) async {
    if (sourceUri.startsWith('file://')) {
      final file = File(Uri.parse(sourceUri).toFilePath());
      if (await file.exists()) {
        await pickWallpaperNight(file);
        return;
      }
    }
    await _saveImageBytes(await _channel.loadContentUriImage(sourceUri), _wallpaperNightFile);
  }

  Future<void> pickVideoWallpaper(File sourceFile) async {
    await _saveVideo(sourceFile, _wallpaperVideoFile);
  }

  Future<void> pickVideoWallpaperDay(File sourceFile) async {
    await _saveVideo(sourceFile, _wallpaperDayVideoFile);
  }

  Future<void> pickVideoWallpaperNight(File sourceFile) async {
    await _saveVideo(sourceFile, _wallpaperNightVideoFile);
  }

  Future<void> _saveImage(File sourceFile, File targetFile) async {
    if (_settingsService.photoWallpaperEnabled) {
      await _settingsService.setPhotoWallpaperEnabled(false);
    }
    if (_settingsService.unsplashSlideshowEnabled) {
      await _settingsService.setUnsplashSlideshowEnabled(false);
    }
    await _replacePairedVideo(targetFile);

    final readStream = sourceFile.openRead();
    final writeStream = targetFile.openWrite();
    await readStream.cast<List<int>>().pipe(writeStream);

    await _refreshImageWallpaper(targetFile);
  }

  Future<void> _saveImageBytes(Uint8List imageBytes, File targetFile) async {
    if (imageBytes.isEmpty) {
      throw StateError('Unable to read the selected image');
    }

    if (_settingsService.photoWallpaperEnabled) {
      await _settingsService.setPhotoWallpaperEnabled(false);
    }
    if (_settingsService.unsplashSlideshowEnabled) {
      await _settingsService.setUnsplashSlideshowEnabled(false);
    }

    await _replacePairedVideo(targetFile);
    await targetFile.writeAsBytes(imageBytes, flush: true);

    await _refreshImageWallpaper(targetFile);
  }

  Future<void> _replacePairedVideo(File targetFile) async {
    // Setting an image means the user no longer wants a video wallpaper, so
    // remove all video wallpaper files (including unrelated ones like the
    // general wallpaper_video when setting wallpaper_day) to prevent stale
    // video playback after switching.
    await cleanVideoWallpaperFiles();
  }

  Future<void> _refreshImageWallpaper(File targetFile) async {
    await FileImage(targetFile).evict();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    _updateWallpaper(force: true);
  }

  Future<void> _saveVideo(File sourceFile, File targetVideoFile) async {
    final pairedImage = _pairedImageForVideo(targetVideoFile);
    if (pairedImage != null && await pairedImage.exists()) {
      await pairedImage.delete();
    }

    if (_settingsService.photoWallpaperEnabled) {
      await _settingsService.setPhotoWallpaperEnabled(false);
    }
    if (_settingsService.unsplashSlideshowEnabled) {
      await _settingsService.setUnsplashSlideshowEnabled(false);
    }

    final readStream = sourceFile.openRead();
    final writeStream = targetVideoFile.openWrite();
    await readStream.cast<List<int>>().pipe(writeStream);

    _updateWallpaper(force: true);
  }

  File? _pairedImageForVideo(File videoFile) {
    if (videoFile.path == _wallpaperVideoFile.path) return _wallpaperFile;
    if (videoFile.path == _wallpaperDayVideoFile.path) return _wallpaperDayFile;
    if (videoFile.path == _wallpaperNightVideoFile.path) return _wallpaperNightFile;
    return null;
  }

  Future<void> setGradient(FLauncherGradient fLauncherGradient) async {
    await cleanImageWallpaperFiles();
    await cleanVideoWallpaperFiles();

    if (_settingsService.photoWallpaperEnabled) {
      await _settingsService.setPhotoWallpaperEnabled(false);
    }
    if (_settingsService.unsplashSlideshowEnabled) {
      await _settingsService.setUnsplashSlideshowEnabled(false);
    }

    await _settingsService.setGradientUuid(fLauncherGradient.uuid);
    // Drop the in-memory wallpaper provider so the gradient is shown instead of
    // the (now deleted) image/video file. _updateWallpaper notifies listeners.
    _updateWallpaper(force: true);
  }

  // Cleaning methods

  Future<void> cleanVideoWallpaperFiles() async {
    if (await _wallpaperVideoFile.exists()) {
      await _wallpaperVideoFile.delete();
    }

    if (await _wallpaperDayVideoFile.exists()) {
      await _wallpaperDayVideoFile.delete();
    }

    if (await _wallpaperNightVideoFile.exists()) {
      await _wallpaperNightVideoFile.delete();
    }
  }

  Future<void> cleanImageWallpaperFiles() async {
    if (await _wallpaperFile.exists()) {
      await _wallpaperFile.delete();
    }

    if (await _wallpaperDayFile.exists()) {
      await _wallpaperDayFile.delete();
    }

    if (await _wallpaperNightFile.exists()) {
      await _wallpaperNightFile.delete();
    }
  }
}
