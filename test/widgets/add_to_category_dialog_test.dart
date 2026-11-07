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
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/add_to_category_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

void main() {
  testWidgets("a Reel section is never offered as a place for an app", (tester) async {
    final appsService = MockAppsService();
    when(appsService.categories).thenReturn([
      fakeCategory(name: "Up next", type: CategoryType.reel),
      fakeCategory(name: "Games", type: CategoryType.row),
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppsService>.value(
        value: appsService,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AddToCategoryDialog(fakeApp(packageName: "com.example.harborlights"))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Games"), findsOneWidget);
    expect(find.text("Up next"), findsNothing);
  });
}
