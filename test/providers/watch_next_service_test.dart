import 'dart:async';

import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

Map<String, dynamic> _row(int id, {int engagement = 1000, int duration = 2700000, String? title}) => {
  'id': id,
  'title': title ?? 'Show $id',
  'contentId': 'plex://server-a/$id',
  'packageName': 'com.edde746.plezy',
  'duration': duration,
  'progressPercent': 0,
  'lastEngagementDate': engagement,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFLauncherChannel channel;
  late List<List<Map<String, dynamic>>> reads;
  late Object? throwNext;

  setUp(() {
    channel = MockFLauncherChannel();
    reads = [];
    throwNext = null;
    when(channel.checkWatchNextPermission()).thenAnswer((_) async => true);
    when(channel.getWatchNextItems()).thenAnswer((_) async {
      final error = throwNext;
      if (error != null) {
        throwNext = null;
        throw error;
      }
      return reads.removeAt(0);
    });
  });

  Future<WatchNextService> loaded(List<Map<String, dynamic>> first) async {
    reads.add(first);
    final service = WatchNextService(channel);
    addTearDown(service.dispose);
    // _init runs the first refresh without awaiting it.
    await pumpEventQueue();
    expect(service.items, hasLength(first.length));
    return service;
  }

  test('a refresh with identical rows sends no notify and the section stays visible', () async {
    final service = await loaded([_row(1), _row(2)]);
    var notifies = 0;
    final visibility = <bool>[];
    service.addListener(() {
      notifies++;
      visibility.add(service.hasVisibleSection);
    });

    // Same rows, only the engagement times moved (a publisher re-sync).
    reads.add([_row(1, engagement: 5000), _row(2, engagement: 6000)]);
    final refresh = service.refreshPermissionAndItems();
    expect(service.hasVisibleSection, isTrue, reason: 'visible while the refresh is in flight');
    await refresh;

    expect(notifies, 0);
    expect(service.hasVisibleSection, isTrue);
    expect(visibility, isEmpty);
  });

  test('a refresh that throws keeps the previous items', () async {
    final service = await loaded([_row(1), _row(2)]);
    throwNext = Exception('provider went away');
    await service.refreshItems();
    expect(service.items.map((i) => i.id), [1, 2]);
    expect(service.hasVisibleSection, isTrue);
  });

  test('a refresh with changed rows notifies with the new order', () async {
    final service = await loaded([_row(1), _row(2)]);
    var notifies = 0;
    service.addListener(() => notifies++);
    reads.add([_row(2), _row(1)]);
    await service.refreshItems();
    expect(service.items.map((i) => i.id), [2, 1]);
    expect(notifies, greaterThan(0));
    expect(service.hasVisibleSection, isTrue);
  });

  test('checkPermission notifies only when the permission changes', () async {
    final service = await loaded([_row(1)]);
    var notifies = 0;
    service.addListener(() => notifies++);
    await service.checkPermission();
    expect(notifies, 0);
    when(channel.checkWatchNextPermission()).thenAnswer((_) async => false);
    await service.checkPermission();
    expect(notifies, 1);
  });

  test('the first load is the only time the section hides', () async {
    final firstRead = Completer<List<Map<String, dynamic>>>();
    when(channel.getWatchNextItems()).thenAnswer((_) => firstRead.future);
    final service = WatchNextService(channel);
    addTearDown(service.dispose);
    await pumpEventQueue();
    expect(service.isLoading, isTrue);
    expect(service.hasVisibleSection, isFalse, reason: 'nothing to show yet');
    firstRead.complete([_row(1)]);
    await pumpEventQueue();
    expect(service.hasVisibleSection, isTrue);

    final secondRead = Completer<List<Map<String, dynamic>>>();
    when(channel.getWatchNextItems()).thenAnswer((_) => secondRead.future);
    final refresh = service.refreshItems();
    await pumpEventQueue();
    expect(service.isLoading, isTrue);
    expect(service.hasVisibleSection, isTrue, reason: 'a refresh keeps the cards');
    secondRead.complete([_row(1)]);
    await refresh;
  });

  test('sameWatchNextContent ignores engagement dates but not order, progress or duration', () {
    WatchNextItem item(Map<String, dynamic> m) => WatchNextItem.fromMap(m);
    expect(
      WatchNextService.sameWatchNextContent(
        [item(_row(1)), item(_row(2))],
        [item(_row(1, engagement: 9)), item(_row(2, engagement: 99))],
      ),
      isTrue,
    );
    expect(
      WatchNextService.sameWatchNextContent([item(_row(1)), item(_row(2))], [item(_row(2)), item(_row(1))]),
      isFalse,
    );
    expect(WatchNextService.sameWatchNextContent([item(_row(1))], [item(_row(1, duration: 1))]), isFalse);
    expect(
      WatchNextService.sameWatchNextContent(
        [item(_row(1))],
        [
          item({..._row(1), 'progressPercent': 40}),
        ],
      ),
      isFalse,
    );
  });
}
