import 'package:flauncher/models/watch_next_item.dart';
import 'package:flutter_test/flutter_test.dart';

String _left(int m) => '$m min left';

void main() {
  test('fromMap without the new fields keeps working', () {
    final item = WatchNextItem.fromMap({'id': 1, 'title': 'Film', 'duration': 6000000, 'progressPercent': 0});
    expect(item.lastPlaybackPosition, isNull);
    expect(item.episodeTitle, isNull);
    expect(item.seasonNumber, isNull);
    expect(item.minutesLeft, isNull);
    expect(item.subtitle(newLabel: 'New', minutesLeftLabel: _left), isNull);
  });

  test('fromMap with the new fields', () {
    final item = WatchNextItem.fromMap({
      'id': 2,
      'title': 'The Expanse',
      'duration': 2700000,
      'lastPlaybackPosition': 1380000,
      'episodeTitle': 'Dulcinea',
      'seasonNumber': '3',
      'episodeNumber': '7',
      'progressPercent': 51,
    });
    expect(item.lastPlaybackPosition, 1380000);
    expect(item.episodeTitle, 'Dulcinea');
    expect(item.seasonNumber, '3');
    expect(item.episodeNumber, '7');
    expect(item.progressPercent, 51);
    expect(WatchNextItem.fromMap(item.toMap()).subtitle(newLabel: 'New', minutesLeftLabel: _left),
        'S3 · E7 · 22 min left');
  });

  test('subtitle: started, new, film, rounding', () {
    WatchNextItem ep({int? pos, int dur = 2700000, String? s = '3', String? e = '7'}) => WatchNextItem(
        id: 1, title: 'T', duration: dur, lastPlaybackPosition: pos, seasonNumber: s, episodeNumber: e);
    expect(ep(pos: 1380000).subtitle(newLabel: 'New', minutesLeftLabel: _left), 'S3 · E7 · 22 min left');
    expect(ep(pos: 0).subtitle(newLabel: 'New', minutesLeftLabel: _left), 'S3 · E7 · New');
    expect(ep(pos: null).subtitle(newLabel: 'New', minutesLeftLabel: _left), 'S3 · E7 · New');
    expect(ep(pos: 2699000).subtitle(newLabel: 'New', minutesLeftLabel: _left), 'S3 · E7 · 1 min left');
    expect(ep(pos: 600000, s: null, e: null, dur: 7200000).subtitle(newLabel: 'New', minutesLeftLabel: _left),
        '110 min left');
    // A film that hasn't been started has nothing useful to say.
    expect(ep(pos: 0, s: null, e: null).subtitle(newLabel: 'New', minutesLeftLabel: _left), isNull);
  });
}
