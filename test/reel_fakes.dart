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

import 'package:flauncher/flauncher_channel.dart';

/// A channel whose Reel calls are answered in memory.
class FakeReelChannel extends FLauncherChannel {
  String? handler;
  bool launchResult;
  Completer<String?>? pending;
  final List<String> resolved = [];
  final List<String> launched = [];

  FakeReelChannel({this.handler, this.launchResult = true});

  @override
  Future<String?> resolveUriHandler(String uri) async {
    resolved.add(uri);
    final wait = pending;
    if (wait != null) return wait.future;
    return handler;
  }

  @override
  Future<bool> launchUri(String uri) async {
    launched.add(uri);
    return launchResult;
  }
}
