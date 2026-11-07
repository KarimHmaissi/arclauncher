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
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/settings_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Settings › Wallpaper › 4K photos: Windows Spotlight or Bing photo of the day.
class PhotoWallpaperPanelPage extends StatelessWidget {
  static const String routeName = "photo_wallpaper_panel";

  const PhotoWallpaperPanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        final source = settings.photoWallpaperSource;
        return Column(
          children: [
            SettingsPageHeader(title: localizations.photoWallpaper),
            Expanded(
              child: ListView(
                children: [
                  RoundedSwitchListTile(
                    autofocus: true,
                    title: Text(localizations.photoWallpaperEnable),
                    secondary: const Icon(Icons.landscape_outlined),
                    value: settings.photoWallpaperEnabled,
                    onChanged: (value) => settings.setPhotoWallpaperEnabled(value),
                  ),
                  FocusableSettingsTile(
                    leading: const Icon(Icons.public),
                    title: Text(localizations.photoWallpaperSource),
                    trailing: Text(
                      source == PhotoSource.bing
                          ? localizations.photoWallpaperSourceBing
                          : localizations.photoWallpaperSourceSpotlight,
                    ),
                    onPressed: () => settings.setPhotoWallpaperSource(source.other),
                  ),
                  FocusableSettingsTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(localizations.wallpaperInterval),
                    trailing: Text(_intervalLabel(localizations, settings.photoWallpaperIntervalMinutes)),
                    onPressed: () => settings.setPhotoWallpaperIntervalMinutes(
                      _nextInterval(settings.photoWallpaperIntervalMinutes),
                    ),
                  ),
                  RoundedSwitchListTile(
                    title: Text(localizations.photoWallpaperShowCredit),
                    secondary: const Icon(Icons.info_outline),
                    value: settings.photoWallpaperShowCredit,
                    onChanged: (value) => settings.setPhotoWallpaperShowCredit(value),
                  ),
                  if (settings.photoWallpaperEnabled)
                    FocusableSettingsTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(localizations.photoWallpaperChangeNow),
                      onPressed: () => _changeNow(context, localizations),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _changeNow(BuildContext context, AppLocalizations localizations) async {
    final service = context.read<WallpaperService>();
    final prevRev = service.wallpaperRevision;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(localizations.photoWallpaperChangeNow),
          ],
        ),
        duration: const Duration(seconds: 10),
      ),
    );
    await service.advancePhotoWallpaper();
    if (context.mounted) {
      final success = service.wallpaperRevision != prevRev;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? localizations.photoWallpaperUpdated : localizations.photoWallpaperFailed),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  static String _intervalLabel(AppLocalizations localizations, int minutes) {
    if (minutes >= 1440) {
      final days = minutes ~/ 1440;
      return days == 1 ? localizations.wallpaperInterval1Day : localizations.wallpaperIntervalDays(days);
    } else if (minutes >= 60) {
      final hours = minutes ~/ 60;
      return hours == 1 ? localizations.wallpaperInterval1Hour : localizations.wallpaperIntervalHours(hours);
    } else {
      return localizations.wallpaperIntervalMinutes(minutes);
    }
  }

  static int _nextInterval(int current) {
    const choices = SettingsService.photoWallpaperIntervalChoices;
    final index = choices.indexOf(current);
    if (index == -1) return choices.first;
    return choices[(index + 1) % choices.length];
  }
}
