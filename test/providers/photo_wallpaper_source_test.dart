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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flauncher/providers/photo_wallpaper_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

final Uint8List _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

/// Image bodies come back as text/plain, as the Spotlight CDN sends them.
http.Response _jpegResponse() => http.Response.bytes(_jpeg, 200, headers: {'content-type': 'text/plain'});

bool _isSpotlightApi(Uri u) => u.host == 'fd.api.iris.microsoft.com';

bool _isBingApi(Uri u) => u.host == 'www.bing.com' && u.path == '/HPImageArchive.aspx';

List<String> _files(Directory dir) =>
    dir.existsSync() ? (dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort()) : [];

void main() {
  late Directory tmp;
  late Directory cacheDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('photo_wallpaper_test');
    cacheDir = Directory('${tmp.path}/photo_wallpaper');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  PhotoWallpaperSource source(
    MockClient client, {
    Locale locale = const Locale('en', 'US'),
    DateTime Function()? now,
    int poolSize = PhotoWallpaperSource.defaultPoolSize,
    int maxNewPerFill = PhotoWallpaperSource.defaultMaxNewPerFill,
  }) => PhotoWallpaperSource(
    cacheDir,
    client: client,
    locale: () => locale,
    now: now,
    poolSize: poolSize,
    maxNewPerFill: maxNewPerFill,
  );

  group('parseSpotlight', () {
    test('reads id, 4K url, title and place with copyright', () {
      final items = PhotoWallpaperSource.parseSpotlight(_fixture('spotlight_ok.json'));
      final raw = (jsonDecode(_fixture('spotlight_ok.json'))['batchrsp']['items'] as List)
          .map((i) => jsonDecode(i['item'] as String)['ad'] as Map)
          .toList();

      expect(items, hasLength(2));
      for (var i = 0; i < 2; i++) {
        final ad = raw[i];
        final place = (ad['iconHoverText'] as String).split('\r\n').first;
        expect(items[i].id, 'sp_${ad['entityId']}');
        expect(items[i].imageUrl, endsWith('_3840x2160.jpg'));
        expect(items[i].source, PhotoSource.spotlight);
        expect(items[i].credit.title, ad['title']);
        expect(items[i].credit.copyright, '$place · ${ad['copyright']}');
      }
    });

    test('returns nothing for error payloads and garbage, without throwing', () {
      expect(PhotoWallpaperSource.parseSpotlight(_fixture('spotlight_error.json')), isEmpty);
      expect(PhotoWallpaperSource.parseSpotlight('{"error":{"code":1010,"msg":"x"}}'), isEmpty);
      expect(PhotoWallpaperSource.parseSpotlight('not json'), isEmpty);
      expect(
        PhotoWallpaperSource.parseSpotlight(
          jsonEncode({
            'batchrsp': {
              'ver': '1.0',
              'items': [
                {'item': '{broken'},
              ],
            },
          }),
        ),
        isEmpty,
      );
    });
  });

  group('parseBing', () {
    test('reads UHD url, stable id and credit', () {
      final items = PhotoWallpaperSource.parseBing(_fixture('bing_ok.json'));

      expect(items, hasLength(3));
      expect(items.first.imageUrl, 'https://www.bing.com/th?id=OHR.DakotaBison_EN-US0710175615_UHD.jpg');
      expect(items.first.id, 'bing_DakotaBison');
      expect(items.first.source, PhotoSource.bing);
      final raw = jsonDecode(_fixture('bing_ok.json'))['images'][0];
      expect(items.first.credit, PhotoCredit(raw['title'] as String, raw['copyright'] as String));
    });

    test('skips images not available as wallpaper', () {
      final json = jsonDecode(_fixture('bing_ok.json'));
      json['images'][1]['wp'] = false;

      expect(PhotoWallpaperSource.parseBing(jsonEncode(json)), hasLength(2));
    });

    test('returns nothing for garbage', () {
      expect(PhotoWallpaperSource.parseBing('not json'), isEmpty);
      expect(PhotoWallpaperSource.parseBing('{"images": 3}'), isEmpty);
    });
  });

  group('markets', () {
    test('spotlightMarket follows the device locale, US without a country', () {
      expect(PhotoWallpaperSource.spotlightMarket(const Locale('en', 'GB')), ('GB', 'en-GB'));
      expect(PhotoWallpaperSource.spotlightMarket(const Locale('de', 'DE')), ('DE', 'de-DE'));
      expect(
        PhotoWallpaperSource.spotlightMarket(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
        ),
        ('CN', 'zh-CN'),
      );
      expect(PhotoWallpaperSource.spotlightMarket(const Locale('en')), ('US', 'en-US'));
    });

    test('bingMarket is a known market or null', () {
      expect(PhotoWallpaperSource.bingMarket(const Locale('en', 'GB')), 'en-GB');
      expect(PhotoWallpaperSource.bingMarket(const Locale('pt', 'BR')), 'pt-BR');
      expect(PhotoWallpaperSource.bingMarket(const Locale('nl', 'NL')), isNull);
    });

    test('Bing requests omit mkt for an unknown market', () async {
      final requests = <Uri>[];
      final client = MockClient((r) async {
        requests.add(r.url);
        if (_isBingApi(r.url)) return http.Response(_fixture('bing_ok.json'), 200);
        return _jpegResponse();
      });

      await source(client, locale: const Locale('nl', 'NL')).fillPool(source: PhotoSource.bing, seen: {});

      final bing = requests.where(_isBingApi).toList();
      expect(bing, hasLength(2));
      for (final u in bing) {
        expect(u.queryParameters.containsKey('mkt'), isFalse);
      }
    });
  });

  group('fillPool', () {
    test('downloads Spotlight photos even though the CDN says text/plain', () async {
      final requests = <Uri>[];
      final client = MockClient((r) async {
        requests.add(r.url);
        if (_isSpotlightApi(r.url)) return http.Response(_fixture('spotlight_ok.json'), 200);
        return _jpegResponse();
      });

      final saved = await source(
        client,
        locale: const Locale('fr', 'FR'),
      ).fillPool(source: PhotoSource.spotlight, seen: {});

      final items = PhotoWallpaperSource.parseSpotlight(_fixture('spotlight_ok.json'));
      expect(saved.map((p) => p.id), items.map((p) => p.id));
      expect(_files(cacheDir), items.map((p) => '${p.id}.jpg').toList()..sort());
      expect(File('${cacheDir.path}/${items.first.id}.jpg').readAsBytesSync(), _jpeg);

      final api = requests.firstWhere(_isSpotlightApi);
      expect(api.path, '/v4/api/selection');
      expect(api.queryParameters, {
        'placement': '88000820',
        'bcnt': '4',
        'country': 'FR',
        'locale': 'fr-FR',
        'fmt': 'json',
      });
      // Never more than three Spotlight calls per fill, and never Bing when Spotlight worked.
      expect(requests.where(_isSpotlightApi).length, lessThanOrEqualTo(3));
      expect(requests.where(_isBingApi), isEmpty);
    });

    test('Spotlight error retries the US market once, then falls back to Bing', () async {
      final requests = <Uri>[];
      final client = MockClient((r) async {
        requests.add(r.url);
        if (_isSpotlightApi(r.url)) return http.Response(_fixture('spotlight_error.json'), 200);
        if (_isBingApi(r.url)) return http.Response(_fixture('bing_ok.json'), 200);
        return _jpegResponse();
      });

      final saved = await source(
        client,
        locale: const Locale('de', 'DE'),
      ).fillPool(source: PhotoSource.spotlight, seen: {});

      expect(_isSpotlightApi(requests[0]), isTrue);
      expect((requests[0].queryParameters['country'], requests[0].queryParameters['locale']), ('DE', 'de-DE'));
      expect(_isSpotlightApi(requests[1]), isTrue);
      expect((requests[1].queryParameters['country'], requests[1].queryParameters['locale']), ('US', 'en-US'));
      expect(_isBingApi(requests[2]), isTrue);
      expect(requests[2].queryParameters['idx'], '0');
      expect(requests[2].queryParameters['mkt'], 'de-DE');
      expect(_isBingApi(requests[3]), isTrue);
      expect(requests[3].queryParameters['idx'], '7');
      expect(requests[4].toString(), 'https://www.bing.com/th?id=OHR.DakotaBison_EN-US0710175615_UHD.jpg');
      expect(requests.where(_isSpotlightApi), hasLength(2));
      expect(saved.first.id, 'bing_DakotaBison');
      expect(_files(cacheDir), contains('bing_DakotaBison.jpg'));
    });

    test('returns nothing and leaves no files when every request fails', () async {
      final failing = MockClient((r) async => http.Response('nope', 500));
      expect(await source(failing).fillPool(source: PhotoSource.spotlight, seen: {}), isEmpty);
      expect(_files(cacheDir), isEmpty);

      final throwing = MockClient((r) async => throw const SocketException('offline'));
      expect(await source(throwing).fillPool(source: PhotoSource.bing, seen: {}), isEmpty);
      expect(_files(cacheDir), isEmpty);
    });

    test('skips photos downloaded before', () async {
      _seed(cacheDir, ['old_a', 'old_b']);
      final items = PhotoWallpaperSource.parseSpotlight(_fixture('spotlight_ok.json'));
      final client = MockClient((r) async {
        if (_isSpotlightApi(r.url)) return http.Response(_fixture('spotlight_ok.json'), 200);
        return _jpegResponse();
      });

      final saved = await source(client).fillPool(source: PhotoSource.spotlight, seen: {items[0].id});

      expect(saved.map((p) => p.id), [items[1].id]);
    });

    test('with an empty pool, photos downloaded before are allowed again', () async {
      final items = PhotoWallpaperSource.parseSpotlight(_fixture('spotlight_ok.json'));
      final client = MockClient((r) async {
        if (_isSpotlightApi(r.url)) return http.Response(_fixture('spotlight_ok.json'), 200);
        return _jpegResponse();
      });

      final saved = await source(client).fillPool(source: PhotoSource.spotlight, seen: {for (final p in items) p.id});

      expect(saved, hasLength(2));
    });

    test('rejects a non-JPEG body, keeps the other candidates and leaves no temp file', () async {
      final items = PhotoWallpaperSource.parseSpotlight(_fixture('spotlight_ok.json'));
      final client = MockClient((r) async {
        if (_isSpotlightApi(r.url)) return http.Response(_fixture('spotlight_ok.json'), 200);
        if (r.url.toString() == items[0].imageUrl) {
          return http.Response('<html>blocked</html>', 200, headers: {'content-type': 'text/html'});
        }
        return _jpegResponse();
      });

      final saved = await source(client).fillPool(source: PhotoSource.spotlight, seen: {});

      expect(saved.map((p) => p.id), [items[1].id]);
      expect(_files(cacheDir), ['${items[1].id}.jpg']);
    });

    test('dedupes the two Bing pages and downloads each photo once', () async {
      final imageGets = <Uri>[];
      final client = MockClient((r) async {
        if (_isBingApi(r.url)) return http.Response(_fixture('bing_ok.json'), 200);
        imageGets.add(r.url);
        return _jpegResponse();
      });

      final saved = await source(client).fillPool(source: PhotoSource.bing, seen: {});

      expect(saved.map((p) => p.id), ['bing_DakotaBison', 'bing_PipiwaiTrail', 'bing_StileCrossing']);
      expect(imageGets, hasLength(3));
      expect(_files(cacheDir), hasLength(3));
    });

    test('downloads at most maxNewPerFill photos while the pool is not full', () async {
      final client = MockClient((r) async {
        if (_isBingApi(r.url)) return http.Response(_fixture('bing_ok.json'), 200);
        return _jpegResponse();
      });

      final saved = await source(client, maxNewPerFill: 2).fillPool(source: PhotoSource.bing, seen: {});

      expect(saved, hasLength(2));
      expect(_files(cacheDir), hasLength(2));
    });

    test('a full pool rotates: the oldest photos make room, the protected one stays', () async {
      _seed(cacheDir, ['old_a', 'old_b', 'old_c']);
      final client = MockClient((r) async {
        if (_isBingApi(r.url)) return http.Response(_fixture('bing_ok.json'), 200);
        return _jpegResponse();
      });

      final saved = await source(client, poolSize: 3).fillPool(source: PhotoSource.bing, seen: {}, protect: {'old_a'});

      expect(saved, hasLength(3));
      final files = _files(cacheDir);
      expect(files, hasLength(3));
      expect(files, contains('old_a.jpg'));
      expect(files, isNot(contains('old_b.jpg')));
      expect(files, isNot(contains('old_c.jpg')));
      expect(files.where((f) => f.endsWith('.part')), isEmpty);
    });

    test('keeps at most poolSize photos over many fills', () async {
      final client = MockClient((r) async {
        if (_isSpotlightApi(r.url)) return http.Response(_fixture('spotlight_ok.json'), 200);
        if (_isBingApi(r.url)) return http.Response(_fixture('bing_ok.json'), 200);
        return _jpegResponse();
      });
      final s = source(client, poolSize: 2);

      for (final src in [PhotoSource.spotlight, PhotoSource.bing, PhotoSource.bing]) {
        await s.fillPool(source: src, seen: {});
      }

      final files = _files(cacheDir);
      expect(files, hasLength(2));
      expect(files.every((f) => f.endsWith('.jpg')), isTrue);
    });

    test('only one fill runs at a time', () async {
      var apiCalls = 0;
      final client = MockClient((r) async {
        if (_isBingApi(r.url)) {
          apiCalls++;
          return http.Response(_fixture('bing_ok.json'), 200);
        }
        return _jpegResponse();
      });
      final s = source(client);

      final first = s.fillPool(source: PhotoSource.bing, seen: {});
      final second = s.fillPool(source: PhotoSource.bing, seen: {});

      expect(identical(first, second), isTrue);
      await first;
      expect(apiCalls, 2);
    });

    test('reuses the fetched photo list for 24 hours', () async {
      var now = DateTime(2026, 1, 1, 12);
      var apiCalls = 0;
      var imageCalls = 0;
      final client = MockClient((r) async {
        if (_isBingApi(r.url)) {
          apiCalls++;
          return http.Response(_fixture('bing_ok.json'), 200);
        }
        imageCalls++;
        return _jpegResponse();
      });
      final s = source(client, now: () => now, maxNewPerFill: 1);

      await s.fillPool(source: PhotoSource.bing, seen: {});
      expect(apiCalls, 2);

      now = now.add(const Duration(hours: 23));
      await s.fillPool(source: PhotoSource.bing, seen: {});
      expect(apiCalls, 2);
      expect(imageCalls, 2);

      now = now.add(const Duration(hours: 2));
      await s.fillPool(source: PhotoSource.bing, seen: {});
      expect(apiCalls, 4);
    });
  });

  group('pickNext', () {
    test('newest unshown first, never the current one, then least recently shown', () {
      _seed(cacheDir, ['c', 'b', 'a']); // a is the newest
      final s = source(MockClient((_) async => http.Response('', 500)));
      final files = s.cachedPhotos();
      expect(files.map(PhotoWallpaperSource.idOf), ['a', 'b', 'c']);

      String? pick(String? current, List<String> shown) =>
          PhotoWallpaperSource.pickNext(files, currentId: current, shownOrder: shown)?.let(PhotoWallpaperSource.idOf);

      expect(pick(null, []), 'a');
      expect(pick('a', ['a']), 'b');
      expect(pick('b', ['a', 'b']), 'c');
      // Everything shown: round robin, the one shown longest ago.
      expect(pick('c', ['a', 'b', 'c']), 'a');
      expect(pick('a', ['b', 'c', 'a']), 'b');
    });

    test('null when the only photo is the one on screen', () {
      _seed(cacheDir, ['a']);
      final s = source(MockClient((_) async => http.Response('', 500)));

      expect(PhotoWallpaperSource.pickNext(s.cachedPhotos(), currentId: 'a', shownOrder: ['a']), isNull);
      expect(PhotoWallpaperSource.pickNext(const [], shownOrder: const []), isNull);
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Writes fake cached photos, the first one oldest.
void _seed(Directory dir, List<String> ids) {
  dir.createSync(recursive: true);
  final base = DateTime(2026, 1, 1);
  for (var i = 0; i < ids.length; i++) {
    File('${dir.path}/${ids[i]}.jpg')
      ..writeAsBytesSync(_jpeg)
      ..setLastModifiedSync(base.add(Duration(minutes: i)));
  }
}
