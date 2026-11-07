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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/photo_wallpaper_source.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/widgets/settings/photo_wallpaper_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

MockSettingsService _settings({bool enabled = false, int interval = 60, PhotoSource source = PhotoSource.spotlight}) {
  final s = MockSettingsService();
  when(s.photoWallpaperEnabled).thenReturn(enabled);
  when(s.photoWallpaperSource).thenReturn(source);
  when(s.photoWallpaperIntervalMinutes).thenReturn(interval);
  when(s.photoWallpaperShowCredit).thenReturn(true);
  return s;
}

Future<void> _pump(WidgetTester tester, MockSettingsService settings, [MockWallpaperService? wallpaper]) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<WallpaperService>.value(value: wallpaper ?? MockWallpaperService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PhotoWallpaperPanelPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("shows every setting, without 'Change photo now' while off", (tester) async {
    await _pump(tester, _settings());

    expect(find.text('4K photos'), findsOneWidget);
    expect(find.text('Show 4K photos'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Varied photos'), findsOneWidget);
    expect(find.text('Change every'), findsOneWidget);
    expect(find.text('1 hour'), findsOneWidget);
    expect(find.text('Show photo credit'), findsOneWidget);
    expect(find.text('Change photo now'), findsNothing);
  });

  testWidgets("shows 'Change photo now' while on", (tester) async {
    await _pump(tester, _settings(enabled: true, source: PhotoSource.bing));

    expect(find.text('Photo of the day'), findsOneWidget);
    expect(find.text('Change photo now'), findsOneWidget);
  });

  testWidgets("the switch has focus and turns 4K photos on", (tester) async {
    final settings = _settings();
    await _pump(tester, settings);

    final focused = FocusManager.instance.primaryFocus?.context;
    final tile = focused?.findAncestorWidgetOfExactType<RoundedSwitchListTile>();
    expect((tile?.title as Text?)?.data, 'Show 4K photos');

    await tester.tap(find.text('Show 4K photos'));
    await tester.pump();

    verify(settings.setPhotoWallpaperEnabled(true));
  });

  testWidgets("the source tile switches between the two sources", (tester) async {
    final settings = _settings();
    await _pump(tester, settings);

    await tester.tap(find.text('Source'));
    await tester.pump();

    verify(settings.setPhotoWallpaperSource(PhotoSource.bing));
  });

  testWidgets("the interval tile cycles through the choices and wraps", (tester) async {
    final settings = _settings(interval: 60);
    await _pump(tester, settings);
    await tester.tap(find.text('Change every'));
    await tester.pump();
    verify(settings.setPhotoWallpaperIntervalMinutes(360));

    final last = _settings(interval: 1440);
    await _pump(tester, last);
    expect(find.text('1 day'), findsOneWidget);
    await tester.tap(find.text('Change every'));
    await tester.pump();
    verify(last.setPhotoWallpaperIntervalMinutes(10));
  });

  testWidgets("the credit switch calls its setter", (tester) async {
    final settings = _settings();
    await _pump(tester, settings);

    await tester.tap(find.text('Show photo credit'));
    await tester.pump();

    verify(settings.setPhotoWallpaperShowCredit(false));
  });

  testWidgets("'Change photo now' advances the photo and reports the result", (tester) async {
    final settings = _settings(enabled: true);
    final wallpaper = MockWallpaperService();
    var revision = 1;
    when(wallpaper.wallpaperRevision).thenAnswer((_) => revision);
    when(wallpaper.advancePhotoWallpaper()).thenAnswer((_) async => revision++);
    await _pump(tester, settings, wallpaper);

    await tester.tap(find.text('Change photo now'));
    await tester.pump();
    await tester.pump();

    verify(wallpaper.advancePhotoWallpaper());
    expect(find.text('Photo changed'), findsOneWidget);
  });
}
