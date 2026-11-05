/*
 * FLauncher
 * Copyright (C) 2021 Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models/watch_next_item.dart';

/// The identity a Watch Next card's focus follows: the publisher's content id
/// (stable across re-syncs), or the provider row id when there is none.
String watchNextFocusKey(WatchNextItem item) {
  final contentId = item.contentId;
  if (contentId != null && contentId.isNotEmpty) return '${item.packageName}|$contentId';
  return 'row:${item.id}';
}

/// One focus node per Watch Next item, keyed by [watchNextFocusKey] rather
/// than by position, so a reorder keeps focus on the same card.
class WatchNextFocusNodes {
  final Map<String, FocusNode> _nodes = {};

  FocusNode nodeFor(WatchNextItem item) {
    final key = watchNextFocusKey(item);
    return _nodes.putIfAbsent(key, () => FocusNode(debugLabel: 'watchNext:$key'));
  }

  /// Drops nodes for items no longer on the row. Disposal waits for the end
  /// of the frame: the card that used a node may still be mounted until then.
  void retainOnly(Iterable<WatchNextItem> items) {
    final keep = items.map(watchNextFocusKey).toSet();
    final stale = _nodes.keys.where((key) => !keep.contains(key)).toList();
    if (stale.isEmpty) return;
    final removed = [for (final key in stale) _nodes.remove(key)!];
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final node in removed) {
        node.dispose();
      }
    });
  }

  @visibleForTesting
  int get length => _nodes.length;

  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
  }
}

/// "Land on Watch Next[0]" requests: Arc's home asks for it on return after a
/// while away, on Home pressed while Arc is in front, and on Back at the root.
/// The Watch Next row (or hero) listens and focuses its first card.
class WatchNextFocusRequests {
  WatchNextFocusRequests._();

  static final ValueNotifier<int> requests = ValueNotifier<int>(0);

  static void focusFirst() => requests.value++;
}
