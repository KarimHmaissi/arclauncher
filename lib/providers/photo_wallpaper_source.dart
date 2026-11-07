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
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Where the 4K photos come from. Each one falls back to the [other].
enum PhotoSource {
  /// Windows Spotlight: varied professional photos.
  spotlight('spotlight'),

  /// Bing photo of the day.
  bing('bing');

  const PhotoSource(this.key);

  final String key;

  static PhotoSource fromKey(String? key) =>
      PhotoSource.values.firstWhere((s) => s.key == key, orElse: () => PhotoSource.spotlight);

  PhotoSource get other => this == spotlight ? bing : spotlight;

  /// Start of the [PhotoWallpaper.id] (and file name) of this source's photos.
  String get idPrefix => this == spotlight ? 'sp_' : 'bing_';
}

/// Shown over the wallpaper and on the screensaver.
class PhotoCredit {
  final String title;
  final String copyright;

  const PhotoCredit(this.title, this.copyright);

  Map<String, String> toJson() => {'title': title, 'copyright': copyright};

  @override
  bool operator ==(Object other) => other is PhotoCredit && other.title == title && other.copyright == copyright;

  @override
  int get hashCode => Object.hash(title, copyright);

  @override
  String toString() => 'PhotoCredit($title, $copyright)';
}

class PhotoWallpaper {
  /// File stem: "sp_<entityId>" or "bing_<Name>".
  final String id;

  /// 3840x2160 jpg.
  final String imageUrl;
  final PhotoCredit credit;
  final PhotoSource source;

  const PhotoWallpaper(this.id, this.imageUrl, this.credit, this.source);
}

final RegExp _unsafeIdChars = RegExp(r'[^A-Za-z0-9_-]');

/// Keeps a pool of 3840x2160 photos from Windows Spotlight or Bing on disk in
/// [cacheDir]. The home wallpaper and the Arc Photos screensaver both pick
/// from it.
class PhotoWallpaperSource {
  PhotoWallpaperSource(
    this.cacheDir, {
    http.Client? client,
    Locale Function()? locale,
    DateTime Function()? now,
    this.poolSize = defaultPoolSize,
    this.maxNewPerFill = defaultMaxNewPerFill,
  }) : _client = client ?? http.Client(),
       _locale = locale ?? (() => PlatformDispatcher.instance.locale),
       _now = now ?? DateTime.now;

  final Directory cacheDir;
  final http.Client _client;
  final Locale Function() _locale;
  final DateTime Function() _now;

  /// Photos kept on disk (2-4 MB each, so about 60-90 MB).
  final int poolSize;

  /// Most photos downloaded by one [fillPool] call while the pool is not full.
  final int maxNewPerFill;

  static const int defaultPoolSize = 24;
  static const int defaultMaxNewPerFill = 8;

  /// New photos fetched by one [fillPool] call once the pool is full; the
  /// oldest ones make room.
  static const int rotateCount = 4;

  /// How long a fetched list of photos is reused before asking again.
  static const Duration poolMaxAge = Duration(hours: 24);
  static const Duration apiTimeout = Duration(seconds: 20);
  static const Duration imageTimeout = Duration(seconds: 90);

  static const int _spotlightMaxCalls = 3;
  static const int _maxDownloadFailures = 3;

  final Map<PhotoSource, List<PhotoWallpaper>> _candidates = {};
  final Map<PhotoSource, DateTime> _candidatesFetchedAt = {};
  Future<List<PhotoWallpaper>>? _filling;

  /// File stem of a cached photo, which is its [PhotoWallpaper.id].
  static String idOf(File f) {
    final name = f.uri.pathSegments.last;
    return name.endsWith('.jpg') ? name.substring(0, name.length - 4) : name;
  }

  /// The photos on disk, newest first.
  List<File> cachedPhotos() {
    if (!cacheDir.existsSync()) return [];
    final entries = [
      for (final f in cacheDir.listSync().whereType<File>())
        if (f.path.endsWith('.jpg')) (f, f.lastModifiedSync()),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in entries) e.$1];
  }

  /// Downloads new photos into the pool: up to [maxNewPerFill] while it holds
  /// fewer than [poolSize], else [rotateCount] that replace the oldest ones.
  /// Photos whose id is in [seen] (downloaded before) are skipped, and those
  /// [protect] returns (on screen) are never pruned; it is asked at each prune,
  /// so a photo shown while the fill runs is safe too. [onSaved] runs after
  /// each photo lands, before the next download. Tries [source], then
  /// [source.other] if [source] fails. Only one fill runs at a time: a call
  /// made while one is running gets that one's result (and its [onSaved]).
  /// Returns the photos saved; never throws.
  Future<List<PhotoWallpaper>> fillPool({
    required PhotoSource source,
    required Set<String> seen,
    Set<String> Function()? protect,
    Future<void> Function(PhotoWallpaper photo)? onSaved,
  }) {
    final running = _filling;
    if (running != null) return running;
    final fill = _fill(source, seen, protect ?? _nothing, onSaved);
    _filling = fill;
    fill.whenComplete(() => _filling = null).ignore();
    return fill;
  }

  static Set<String> _nothing() => const {};

  Future<List<PhotoWallpaper>> _fill(
    PhotoSource source,
    Set<String> seen,
    Set<String> Function() protect,
    Future<void> Function(PhotoWallpaper photo)? onSaved,
  ) async {
    final saved = <PhotoWallpaper>[];
    try {
      final count = cachedPhotos().length;
      final want = count < poolSize ? min(poolSize - count, maxNewPerFill) : min(rotateCount, maxNewPerFill);
      // With fewer than two photos on disk there is nothing to rotate through, so
      // photos downloaded before are welcome again rather than showing nothing.
      final exclude = count < 2 ? <String>{} : {...seen};
      for (final s in [source, source.other]) {
        final failed = await _fillFrom(s, want - saved.length, exclude, protect, onSaved, saved);
        if (!failed) break;
      }
    } catch (e) {
      debugPrint("Photo wallpaper: $e");
    } finally {
      await _prune(protect);
    }
    return saved;
  }

  /// Downloads up to [want] photos from [source] into [saved]. Returns true
  /// when the source failed (no photo list, or every download failed), so the
  /// caller tries the other source.
  Future<bool> _fillFrom(
    PhotoSource source,
    int want,
    Set<String> exclude,
    Set<String> Function() protect,
    Future<void> Function(PhotoWallpaper photo)? onSaved,
    List<PhotoWallpaper> saved,
  ) async {
    if (want <= 0) return false;
    var refreshed = false;
    final fetchedAt = _candidatesFetchedAt[source];
    if ((_candidates[source]?.isEmpty ?? true) || fetchedAt == null || _now().difference(fetchedAt) >= poolMaxAge) {
      await _refresh(source, exclude, want);
      refreshed = true;
    }
    if (_candidates[source]?.isEmpty ?? true) return true;

    var added = 0;
    var failures = 0;
    while (added < want && failures < _maxDownloadFailures) {
      var candidate = _pick(source, exclude);
      if (candidate == null && !refreshed) {
        // Everything listed is already in the pool or was shown before: ask for more once.
        await _refresh(source, exclude, want - added);
        refreshed = true;
        candidate = _pick(source, exclude);
      }
      if (candidate == null) break;

      final photo = candidate;
      _candidates[source]?.removeWhere((p) => p.id == photo.id);
      exclude.add(photo.id);
      if (await _download(photo) != null) {
        saved.add(photo);
        added++;
        await _prune(protect);
        if (onSaved != null) {
          try {
            await onSaved(photo);
          } catch (e) {
            debugPrint("Photo wallpaper: $e");
          }
        }
      } else {
        failures++;
      }
    }
    return added == 0 && failures > 0;
  }

  bool _onDisk(String id) => File("${cacheDir.path}/$id.jpg").existsSync();

  PhotoWallpaper? _pick(PhotoSource source, Set<String> exclude) {
    for (final p in _candidates[source] ?? const <PhotoWallpaper>[]) {
      if (!exclude.contains(p.id) && !_onDisk(p.id)) return p;
    }
    return null;
  }

  Future<void> _refresh(PhotoSource source, Set<String> exclude, int want) async {
    final fetched = switch (source) {
      PhotoSource.spotlight => await _fetchSpotlight(exclude, want),
      PhotoSource.bing => await _fetchBing(),
    };
    final byId = <String, PhotoWallpaper>{};
    for (final p in fetched) {
      byId.putIfAbsent(p.id, () => p);
    }
    _candidates[source] = byId.values.toList();
    if (byId.isNotEmpty) {
      _candidatesFetchedAt[source] = _now();
    } else {
      _candidatesFetchedAt.remove(source);
    }
  }

  Future<List<PhotoWallpaper>> _fetchSpotlight(Set<String> exclude, int want) async {
    var (country, locale) = spotlightMarket(_locale());
    final items = <PhotoWallpaper>[];
    int fresh() => {
      for (final p in items)
        if (!exclude.contains(p.id) && !_onDisk(p.id)) p.id,
    }.length;

    for (var call = 0; call < _spotlightMaxCalls; call++) {
      var batch = await _getSpotlight(country, locale);
      if (call == 0 && batch.isEmpty) {
        // Some markets have no Spotlight content (error 2040): the US feed always does.
        if (country != 'US' || locale != 'en-US') {
          country = 'US';
          locale = 'en-US';
          batch = await _getSpotlight(country, locale);
        }
        if (batch.isEmpty) break;
      }
      items.addAll(batch);
      if (fresh() >= want) break;
    }
    return items;
  }

  Future<List<PhotoWallpaper>> _getSpotlight(String country, String locale) async {
    final body = await _getText(
      Uri.https('fd.api.iris.microsoft.com', '/v4/api/selection', {
        'placement': '88000820',
        'bcnt': '4',
        'country': country,
        'locale': locale,
        'fmt': 'json',
      }),
    );
    return body == null ? const [] : parseSpotlight(body);
  }

  Future<List<PhotoWallpaper>> _fetchBing() async {
    final mkt = bingMarket(_locale());
    final items = <PhotoWallpaper>[];
    for (final idx in const ['0', '7']) {
      final body = await _getText(
        Uri.https('www.bing.com', '/HPImageArchive.aspx', {
          'format': 'js',
          'idx': idx,
          'n': '8',
          if (mkt != null) 'mkt': mkt,
        }),
      );
      if (body != null) items.addAll(parseBing(body));
    }
    return items;
  }

  /// Body of a 200 response, or null on any failure.
  Future<String?> _getText(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(apiTimeout);
      if (response.statusCode != 200) {
        debugPrint("Photo wallpaper: ${uri.host} answered ${response.statusCode}");
        return null;
      }
      return response.body;
    } catch (e) {
      debugPrint("Photo wallpaper: $e");
      return null;
    }
  }

  /// Saves [photo] as `<id>.jpg`, or returns null if it is not a JPEG.
  Future<File?> _download(PhotoWallpaper photo) async {
    final tmp = File("${cacheDir.path}/${photo.id}.part");
    try {
      final response = await _client.get(Uri.parse(photo.imageUrl)).timeout(imageTimeout);
      final bytes = response.bodyBytes;
      // The Spotlight CDN sends text/plain, so check the JPEG magic bytes instead of the content type.
      if (response.statusCode != 200 || bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        debugPrint("Photo wallpaper: rejected ${photo.id} (${response.statusCode})");
        return null;
      }
      await cacheDir.create(recursive: true);
      // Write to a temp name first so a half-written file is never displayed.
      await tmp.writeAsBytes(bytes, flush: true);
      return await tmp.rename("${cacheDir.path}/${photo.id}.jpg");
    } catch (e) {
      debugPrint("Photo wallpaper: $e");
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Deletes temp files and the oldest photos beyond [poolSize], never one [protect] returns.
  Future<void> _prune(Set<String> Function() protect) async {
    try {
      if (!await cacheDir.exists()) return;
      for (final f in cacheDir.listSync().whereType<File>().where((f) => f.path.endsWith('.part'))) {
        await f.delete();
      }
      final photos = cachedPhotos();
      var excess = photos.length - poolSize;
      final keep = protect();
      for (final f in photos.reversed) {
        if (excess <= 0) break;
        if (keep.contains(idOf(f))) continue;
        await f.delete();
        excess--;
      }
    } catch (e) {
      debugPrint("Photo wallpaper: $e");
    }
  }

  /// The next photo to show from [newestFirst]: the newest one not in
  /// [shownOrder], else the one shown longest ago. Never [currentId]. Null when
  /// there is no other photo.
  static File? pickNext(List<File> newestFirst, {String? currentId, required List<String> shownOrder}) {
    File? best;
    var bestRank = 0;
    for (final f in newestFirst) {
      final id = idOf(f);
      if (id == currentId) continue;
      // Never shown ranks -1, so it beats everything shown; ties go to the newer photo.
      final rank = shownOrder.indexOf(id);
      if (best == null || rank < bestRank) {
        best = f;
        bestRank = rank;
      }
    }
    return best;
  }

  /// Parses a Spotlight v4 `selection` response. Never throws.
  @visibleForTesting
  static List<PhotoWallpaper> parseSpotlight(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return const [];
      final batch = json['batchrsp'];
      if (batch is! Map) return const [];
      final items = batch['items'];
      if (items is! List || items.isEmpty) return const [];

      final result = <PhotoWallpaper>[];
      for (final item in items) {
        try {
          final ad = (jsonDecode((item as Map)['item'] as String) as Map)['ad'] as Map;
          final asset = _nonEmpty((ad['landscapeImage'] as Map?)?['asset']);
          final entityId = _nonEmpty(ad['entityId'])?.replaceAll(_unsafeIdChars, '');
          final title = _nonEmpty(ad['title']);
          final copyright = _nonEmpty(ad['copyright']);
          if (asset == null || entityId == null || entityId.isEmpty || title == null || copyright == null) continue;

          final hover = ad['iconHoverText'];
          String? place;
          if (hover is String) {
            final first = hover.split('\r\n').first.trim();
            if (first.isNotEmpty && !first.startsWith('©')) place = first;
          }
          result.add(
            PhotoWallpaper(
              "sp_$entityId",
              asset,
              PhotoCredit(title, place != null ? "$place · $copyright" : copyright),
              PhotoSource.spotlight,
            ),
          );
        } catch (_) {
          // Skip a malformed item, keep the others.
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// Parses a Bing `HPImageArchive.aspx?format=js` response. Never throws.
  @visibleForTesting
  static List<PhotoWallpaper> parseBing(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return const [];
      final images = json['images'];
      if (images is! List) return const [];

      final result = <PhotoWallpaper>[];
      for (final image in images) {
        try {
          if (image is! Map || image['wp'] != true) continue;
          final urlbase = _nonEmpty(image['urlbase']);
          if (urlbase == null) continue;
          var name = urlbase.startsWith('/th?id=OHR.') ? urlbase.substring('/th?id=OHR.'.length) : urlbase;
          final cut = name.lastIndexOf('_');
          if (cut >= 0) name = name.substring(0, cut);
          name = name.replaceAll(_unsafeIdChars, '');
          if (name.isEmpty) continue;
          result.add(
            PhotoWallpaper(
              "bing_$name",
              "https://www.bing.com${urlbase}_UHD.jpg",
              PhotoCredit((image['title'] as String?) ?? '', (image['copyright'] as String?) ?? ''),
              PhotoSource.bing,
            ),
          );
        } catch (_) {
          // Skip a malformed item, keep the others.
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// Spotlight country and locale for the device locale, `US`/`<lang>-US` without a country.
  @visibleForTesting
  static (String country, String locale) spotlightMarket(Locale l) {
    final cc = l.countryCode?.toUpperCase();
    return cc == null || cc.isEmpty ? ('US', '${l.languageCode}-US') : (cc, '${l.languageCode}-$cc');
  }

  static const Set<String> _bingMarkets = {
    'en-US',
    'en-GB',
    'de-DE',
    'fr-FR',
    'ja-JP',
    'zh-CN',
    'en-AU',
    'en-CA',
    'en-IN',
    'en-NZ',
    'fr-CA',
    'it-IT',
    'es-ES',
    'pt-BR',
  };

  /// Bing market for the device locale, or null to let Bing pick one from the IP address.
  @visibleForTesting
  static String? bingMarket(Locale l) {
    final m = '${l.languageCode}-${l.countryCode?.toUpperCase()}';
    return _bingMarkets.contains(m) ? m : null;
  }

  static String? _nonEmpty(Object? value) => value is String && value.isNotEmpty ? value : null;
}
