import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/watch_next_focus.dart';
import 'package:flauncher/widgets/watch_next_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';
import 'watch_next_hero_test.dart' show TestWatchNextService, TestAppsService;

WatchNextItem _item(int id) => WatchNextItem(
      id: id,
      title: 'Show $id',
      packageName: 'com.edde746.plezy',
      contentId: 'plex://server-a/$id',
      duration: 2700000,
    );

String? _focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  late MockSettingsService settings;
  late TestWatchNextService service;

  setUp(() {
    settings = MockSettingsService();
    when(settings.showWatchNextSection).thenReturn(true);
    when(settings.watchNextBigPictureMode).thenReturn(false);
    when(settings.showFocusBorders).thenReturn(true);
    when(settings.focusBorderThickness).thenReturn(1.5);
    service = TestWatchNextService();
  });

  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<WatchNextService>.value(value: service),
          ChangeNotifierProvider<AppsService>.value(value: TestAppsService()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: WatchNextRow()),
        ),
      );

  testWidgets('focusFirst lands on Watch Next[0]', (tester) async {
    service.testItems = [_item(1), _item(2), _item(3)];
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    WatchNextFocusRequests.focusFirst();
    await tester.pumpAndSettle();
    expect(_focusedLabel(), contains('plex://server-a/1'));
  });

  testWidgets('after a same-length reorder, focus stays on the same contentId', (tester) async {
    service.testItems = [_item(1), _item(2), _item(3)];
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    WatchNextFocusRequests.focusFirst();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focusedLabel(), contains('plex://server-a/2'));

    service.testItems = [_item(2), _item(1), _item(3)];
    await tester.pumpAndSettle();
    expect(_focusedLabel(), contains('plex://server-a/2'));

    // Land again: now the first card is item 2's.
    WatchNextFocusRequests.focusFirst();
    await tester.pumpAndSettle();
    expect(_focusedLabel(), contains('plex://server-a/2'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focusedLabel(), contains('plex://server-a/1'));
  });

  testWidgets('a removed card gives its node back without breaking the row', (tester) async {
    service.testItems = [_item(1), _item(2)];
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    service.testItems = [_item(2)];
    await tester.pumpAndSettle();
    WatchNextFocusRequests.focusFirst();
    await tester.pumpAndSettle();
    expect(_focusedLabel(), contains('plex://server-a/2'));
    expect(tester.takeException(), isNull);
  });

  test('watchNextFocusKey uses package + content id, else the row id', () {
    expect(watchNextFocusKey(_item(7)), 'com.edde746.plezy|plex://server-a/7');
    expect(watchNextFocusKey(WatchNextItem(id: 9, title: 'x')), 'row:9');
  });
}
