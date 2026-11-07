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

import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/reel_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../reel_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("the Reel link is plezy://reel", () {
    expect(ReelService.reelUri, "plezy://reel");
  });

  test("CategoryType.reel is stored after the upstream layouts", () {
    // Categories store their type by index: the upstream values must keep theirs.
    expect(CategoryType.row.index, 0);
    expect(CategoryType.grid.index, 1);
    expect(CategoryType.reel.index, 2);
  });

  test("refresh marks the Reel available while an app handles the link", () async {
    final channel = FakeReelChannel(handler: "com.example.viewer");
    final service = ReelService(channel, listenToLifecycle: false);
    var notified = 0;
    service.addListener(() => notified++);

    await service.refresh();

    expect(service.available, isTrue);
    expect(service.handlerPackage, "com.example.viewer");
    expect(channel.resolved, ["plezy://reel"]);
    expect(notified, 1);

    channel.handler = null;
    await service.refresh();

    expect(service.available, isFalse);
    expect(notified, 2);
  });

  test("refresh does not notify when nothing changed", () async {
    final channel = FakeReelChannel(handler: null);
    final service = ReelService(channel, listenToLifecycle: false);
    var notified = 0;
    service.addListener(() => notified++);

    await service.refresh();
    await service.refresh();

    expect(service.available, isFalse);
    expect(notified, 0);
  });

  test("onAppsChanged re-checks only when the app count changes", () async {
    final channel = FakeReelChannel(handler: "com.example.viewer");
    final service = ReelService(channel, listenToLifecycle: false);

    service.onAppsChanged(4);
    service.onAppsChanged(4);
    await pumpEventQueue();
    expect(channel.resolved.length, 1);

    service.onAppsChanged(5);
    await pumpEventQueue();
    expect(channel.resolved.length, 2);
  });

  test("a slower, older check never overwrites a newer answer", () async {
    final channel = FakeReelChannel(handler: "com.example.viewer");
    final firstAnswer = Completer<String?>();
    channel.pending = firstAnswer;
    final service = ReelService(channel, listenToLifecycle: false);

    final first = service.refresh();
    channel.pending = null;
    channel.handler = null;
    await service.refresh();
    firstAnswer.complete("com.example.viewer");
    await first;

    expect(service.available, isFalse);
  });

  test("open fires plezy://reel", () async {
    final channel = FakeReelChannel(handler: "com.example.viewer");
    final service = ReelService(channel, listenToLifecycle: false);
    await service.refresh();

    expect(await service.open(), isTrue);
    expect(channel.launched, ["plezy://reel"]);
  });

  test("a failed open re-checks, so the tile hides once Plezy is gone", () async {
    final channel = FakeReelChannel(handler: "com.example.viewer");
    final service = ReelService(channel, listenToLifecycle: false);
    await service.refresh();
    expect(service.available, isTrue);

    channel.handler = null;
    channel.launchResult = false;
    expect(await service.open(), isFalse);

    expect(service.available, isFalse);
  });
}
