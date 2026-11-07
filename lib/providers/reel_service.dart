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

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/widgets.dart';

/// Fork: whether The Reel can be opened, and opening it.
///
/// The Reel lives in Plezy and opens with `plezy://reel` (Plezy's
/// `lib/services/deep_links/deep_link.dart`). A section of type
/// `CategoryType.reel` shows its tile only while some installed app handles
/// that link, so without Plezy the tile is simply not there.
///
/// Availability is checked at start, whenever the installed app count
/// changes ([onAppsChanged]), whenever Arc comes back to the front, and after
/// a launch that failed.
class ReelService extends ChangeNotifier {
  static const String reelUri = 'plezy://reel';

  final FLauncherChannel _channel;
  AppLifecycleListener? _lifecycleListener;

  bool _available = false;
  String? _handlerPackage;
  int? _lastAppCount;
  int _refreshGeneration = 0;
  bool _disposed = false;

  ReelService(this._channel, {bool listenToLifecycle = true}) {
    if (listenToLifecycle) {
      _lifecycleListener = AppLifecycleListener(onResume: refresh);
    }
  }

  /// True while an installed app handles [reelUri].
  bool get available => _available;

  /// The package that handles [reelUri], for logs.
  String? get handlerPackage => _handlerPackage;

  /// Re-checks availability when the number of installed apps changed, so
  /// installing or removing Plezy shows or hides the tile.
  void onAppsChanged(int appCount) {
    if (_lastAppCount == appCount) return;
    _lastAppCount = appCount;
    refresh();
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    final handler = await _channel.resolveUriHandler(reelUri);
    // A newer refresh started meanwhile: its answer wins.
    if (_disposed || generation != _refreshGeneration) return;
    final available = handler != null;
    if (available != _available || handler != _handlerPackage) {
      debugPrint('ArcReel: $reelUri handler=${handler ?? 'none'} available=$available');
      _available = available;
      _handlerPackage = handler;
      notifyListeners();
    }
  }

  /// Opens The Reel. False when it could not be started; the tile then
  /// re-checks and hides itself if Plezy has gone.
  Future<bool> open() async {
    final started = await _channel.launchUri(reelUri);
    debugPrint('ArcReel: open $reelUri started=$started');
    if (!started) await refresh();
    return started;
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycleListener?.dispose();
    super.dispose();
  }
}
