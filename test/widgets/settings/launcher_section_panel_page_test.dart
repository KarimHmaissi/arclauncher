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
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/reel_service.dart';
import 'package:flauncher/widgets/settings/launcher_section_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.dart';
import '../../mocks.mocks.dart';
import '../../reel_fakes.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.physicalSizeTestValue = Size(1280, 720);
    binding.window.devicePixelRatioTestValue = 1.0;
    // Scale-down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("Category is displayed", (tester) async {
    final appsService = MockAppsService();
    final favoritesCategory =
        fakeCategory(name: "Favorites", sort: CategorySort.alphabetical, type: CategoryType.grid, columnsCount: 6);
    when(appsService.launcherSections).thenReturn([
      favoritesCategory,
      fakeCategory(name: "Applications"),
    ]);

    await _pumpWidgetWithProviders(tester, appsService, 0);

    expect(find.text("Favorites"), findsWidgets);
    expect(find.text("Alphabetical"), findsOneWidget);
    expect(find.text("Grid"), findsOneWidget);
    expect(find.text("6"), findsOneWidget);
  });

  testWidgets("Spacer is displayed", (tester) async {
    final appsService = MockAppsService();
    final spacer = LauncherSpacer(id: 1, height: 20);
    when(appsService.launcherSections).thenReturn([
      spacer,
    ]);

    await _pumpWidgetWithProviders(tester, appsService, 0);

    expect(find.text("20"), findsOneWidget);
  });

  testWidgets("'Delete' calls AppsService.deleteSection", (tester) async {
    final appsService = MockAppsService();
    final favoritesCategory =
        fakeCategory(name: "Favorites", sort: CategorySort.alphabetical, type: CategoryType.row, rowHeight: 110);
    when(appsService.launcherSections).thenReturn([
      favoritesCategory,
    ]);
    when(appsService.deleteSection(0)).thenAnswer((_) async {});

    await _pumpWidgetWithProviders(tester, appsService, 0);

    final deleteFinder = find.widgetWithText(FilledButton, "Delete");
    expect(deleteFinder, findsOneWidget);
    await tester.tap(deleteFinder);
    await tester.pumpAndSettle();

    verify(appsService.deleteSection(0)).called(1);
  });

  group("Reel layout", () {
    Future<ReelService> reelService({String? handler}) async {
      final service = ReelService(FakeReelChannel(handler: handler), listenToLifecycle: false);
      await service.refresh();
      return service;
    }

    Future<void> openLayoutMenu(WidgetTester tester) async {
      await tester.tap(find.byType(DropdownButtonFormField<CategoryType>));
      await tester.pumpAndSettle();
    }

    testWidgets("is offered while Plezy can open the Reel", (tester) async {
      final appsService = MockAppsService();
      when(appsService.launcherSections).thenReturn([]);

      await _pumpWidgetWithProviders(tester, appsService, null, await reelService(handler: "com.example.viewer"));
      await openLayoutMenu(tester);

      expect(find.text("The Reel (opens Plezy)"), findsOneWidget);
    });

    testWidgets("is not offered without Plezy", (tester) async {
      final appsService = MockAppsService();
      when(appsService.launcherSections).thenReturn([]);

      await _pumpWidgetWithProviders(tester, appsService, null, await reelService(handler: null));
      await openLayoutMenu(tester);

      expect(find.text("The Reel (opens Plezy)"), findsNothing);
      expect(find.text("Grid"), findsWidgets);
    });

    testWidgets("an existing Reel section shows its layout even without Plezy", (tester) async {
      final appsService = MockAppsService();
      when(appsService.launcherSections)
          .thenReturn([fakeCategory(name: "Up next", type: CategoryType.reel, rowHeight: 120)]);

      await _pumpWidgetWithProviders(tester, appsService, 0, await reelService(handler: null));

      expect(find.text("The Reel (opens Plezy)"), findsOneWidget);
      // Sized by row height; sort doesn't apply to a tile with no apps.
      expect(find.text("120"), findsOneWidget);
      expect(find.text("Sort"), findsNothing);
    });

    testWidgets("choosing it names a new section after the Reel and saves that layout", (tester) async {
      final appsService = MockAppsService();
      final created = fakeCategory(name: "The Reel", type: CategoryType.reel);
      when(appsService.launcherSections).thenReturn([created]);
      when(appsService.categories).thenReturn([created]);
      when(appsService.addCategory(any,
              sort: anyNamed('sort'),
              type: anyNamed('type'),
              columnsCount: anyNamed('columnsCount'),
              rowHeight: anyNamed('rowHeight')))
          .thenAnswer((_) async => created.id);

      await _pumpWidgetWithProviders(tester, appsService, null, await reelService(handler: "com.example.viewer"));
      await openLayoutMenu(tester);
      await tester.tap(find.text("The Reel (opens Plezy)").last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, "The Reel"), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(FilledButton, "Save"));
      await tester.tap(find.widgetWithText(FilledButton, "Save"));
      await tester.pumpAndSettle();

      verify(appsService.addCategory("The Reel",
              sort: anyNamed('sort'),
              type: CategoryType.reel,
              columnsCount: anyNamed('columnsCount'),
              rowHeight: anyNamed('rowHeight')))
          .called(1);
      verifyNever(appsService.autoPopulateCategory(any));
    });

    testWidgets("turning the All Apps section into a Reel renames it, so new apps never go into a hidden section",
        (tester) async {
      final appsService = MockAppsService();
      final allApps = fakeCategory(name: "All Apps", type: CategoryType.grid);
      when(appsService.launcherSections).thenReturn([allApps]);
      when(appsService.updateCategory(any, any, any, any, any, any)).thenAnswer((_) async {});

      await _pumpWidgetWithProviders(tester, appsService, 0, await reelService(handler: "com.example.viewer"));
      await openLayoutMenu(tester);
      await tester.tap(find.text("The Reel (opens Plezy)").last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(FilledButton, "Save"));
      await tester.tap(find.widgetWithText(FilledButton, "Save"));
      await tester.pumpAndSettle();

      verify(appsService.updateCategory(allApps.id, "The Reel", any, CategoryType.reel, any, any)).called(1);
    });

    testWidgets("a Reel section can't be saved under the All Apps name", (tester) async {
      final appsService = MockAppsService();
      final reel = fakeCategory(name: "Up next", type: CategoryType.reel);
      when(appsService.launcherSections).thenReturn([reel]);

      await _pumpWidgetWithProviders(tester, appsService, 0, await reelService(handler: "com.example.viewer"));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text("All Apps").last);
      await tester.pumpAndSettle();

      final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, "Save"));
      expect(save.onPressed, isNull);
    });
  });
}

Future<void> _pumpWidgetWithProviders(WidgetTester tester, AppsService appsService, int? sectionIndex,
    [ReelService? reelService]) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        if (reelService != null) ChangeNotifierProvider<ReelService>.value(value: reelService),
      ],
      builder: (_, __) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: LauncherSectionPanelPage(sectionIndex: sectionIndex)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
