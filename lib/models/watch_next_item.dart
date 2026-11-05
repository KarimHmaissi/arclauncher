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

class WatchNextItem {
  final int id;
  final String title;
  final String? description;
  final String? posterUri;
  final String? backdropUri;
  final String? packageName;
  final String? contentId;
  final int? progressPercent;
  final int? duration;
  final DateTime? lastEngagementDate;
  final String? intentUri;
  final int? watchNextType;
  final String? aspectRatio;
  final int? lastPlaybackPosition;
  final String? episodeTitle;
  final String? seasonNumber;
  final String? episodeNumber;

  WatchNextItem({
    required this.id,
    required this.title,
    this.description,
    this.posterUri,
    this.backdropUri,
    this.packageName,
    this.contentId,
    this.progressPercent,
    this.duration,
    this.lastEngagementDate,
    this.intentUri,
    this.watchNextType,
    this.aspectRatio,
    this.lastPlaybackPosition,
    this.episodeTitle,
    this.seasonNumber,
    this.episodeNumber,
  });

  /// Minutes still to watch, rounded up; null without a usable position.
  int? get minutesLeft {
    final total = duration;
    final position = lastPlaybackPosition;
    if (total == null || total <= 0 || position == null || position <= 0) return null;
    final remaining = total - position;
    if (remaining <= 0) return 0;
    return (remaining / 60000).ceil();
  }

  /// The card's second line: "S3 · E7 · 22 min left", or "S3 · E7 · New" for
  /// an episode that hasn't been started. Null when the publisher gave
  /// nothing to say (the card then keeps its generic label).
  String? subtitle({required String newLabel, required String Function(int minutes) minutesLeftLabel}) {
    final parts = <String>[];
    final season = seasonNumber?.trim();
    final episode = episodeNumber?.trim();
    if (season != null && season.isNotEmpty) parts.add('S$season');
    if (episode != null && episode.isNotEmpty) parts.add('E$episode');
    final left = minutesLeft;
    if (left != null) {
      parts.add(minutesLeftLabel(left));
    } else if (parts.isNotEmpty && (lastPlaybackPosition ?? 0) == 0) {
      parts.add(newLabel);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  bool get hasImage {
    final poster = posterUri?.trim();
    final backdrop = backdropUri?.trim();
    return (poster != null && poster.isNotEmpty) || (backdrop != null && backdrop.isNotEmpty);
  }

  factory WatchNextItem.fromMap(Map<dynamic, dynamic> map) {
    return WatchNextItem(
      id: map['id'] ?? 0,
      title: map['title'] ?? '',
      description: map['description'],
      posterUri: map['posterUri'],
      backdropUri: map['backdropUri'],
      packageName: map['packageName'],
      contentId: map['contentId'],
      progressPercent: map['progressPercent'],
      duration: map['duration'],
      lastEngagementDate: map['lastEngagementDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastEngagementDate'])
          : null,
      intentUri: map['intentUri'],
      watchNextType: map['watchNextType'],
      aspectRatio: map['aspectRatio'],
      lastPlaybackPosition: map['lastPlaybackPosition'],
      episodeTitle: map['episodeTitle'],
      seasonNumber: map['seasonNumber']?.toString(),
      episodeNumber: map['episodeNumber']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'posterUri': posterUri,
      'backdropUri': backdropUri,
      'packageName': packageName,
      'contentId': contentId,
      'progressPercent': progressPercent,
      'duration': duration,
      'lastEngagementDate': lastEngagementDate?.millisecondsSinceEpoch,
      'intentUri': intentUri,
      'watchNextType': watchNextType,
      'aspectRatio': aspectRatio,
      'lastPlaybackPosition': lastPlaybackPosition,
      'episodeTitle': episodeTitle,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
    };
  }
}
