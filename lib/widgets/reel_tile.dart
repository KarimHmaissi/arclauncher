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

import 'package:flauncher/actions.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/reel_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/app_card_contour_painter.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';

const _validationKeys = [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA];

/// Fork: the one card of a `CategoryType.reel` section. OK opens The Reel in
/// Plezy. Sized and focused like a row app card; the art is drawn in code.
class ReelTile extends StatefulWidget {
  final Category category;
  final bool handleUpNavigationToSettings;
  final VoidCallback? onFocused;

  const ReelTile({super.key, required this.category, this.handleUpNavigationToSettings = false, this.onFocused});

  @override
  State<ReelTile> createState() => _ReelTileState();
}

class _ReelTileState extends State<ReelTile> {
  static const double _focusedScale = 1.07;
  static const Duration _focusDuration = Duration(milliseconds: 180);
  static const Duration _pressDuration = Duration(milliseconds: 150);

  final FocusNode _focusNode = FocusNode(debugLabel: 'ReelTile');
  bool _focused = false;
  bool _pressed = false;
  bool _traditionalHighlight = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    final traditional = mode == FocusHighlightMode.traditional;
    if (traditional != _traditionalHighlight) setState(() => _traditionalHighlight = traditional);
  }

  @override
  Widget build(BuildContext context) {
    final (String accentHex, bool showFocusBorders, double borderThickness) = context
        .select<SettingsService, (String, bool, double)>(
          (s) => (s.accentColorHex, s.showFocusBorders, s.focusBorderThickness),
        );
    final accent = Color(int.parse('FF$accentHex', radix: 16));
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final highlight = _focused && _traditionalHighlight;
    final label = AppLocalizations.of(context)!.reelTileTitle;
    final height = widget.category.rowHeight.toDouble();

    return FocusKeyboardListener(
      onPressed: _onKey,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          height: height,
          width: height * kAppCardAspectRatio,
          child: AnimatedScale(
            scale: _pressed ? 0.9 : (highlight ? _focusedScale : 1.0),
            duration: reduceMotion ? Duration.zero : (_pressed ? _pressDuration : _focusDuration),
            curve: Curves.easeOutCubic,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Material(
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  elevation: highlight ? 7 : 4,
                  shadowColor: Colors.black,
                  child: InkWell(
                    focusNode: _focusNode,
                    focusColor: Colors.transparent,
                    onTap: _open,
                    onFocusChange: _onFocusChange,
                    child: Semantics(
                      button: true,
                      label: label,
                      child: CustomPaint(
                        painter: ReelTileArtPainter(accent: accent, surface: Theme.of(context).colorScheme.surface),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                shadows: const [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 6)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (highlight && showFocusBorders)
                  IgnorePointer(
                    child: CustomPaint(
                      foregroundPainter: AppCardContourPainter(strokeWidth: borderThickness, accentColor: accent),
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onFocusChange(bool focused) {
    if (focused != _focused) setState(() => _focused = focused);
    if (!focused) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      curve: Curves.easeInOut,
      duration: const Duration(milliseconds: 220),
    );
    widget.onFocused?.call();
  }

  KeyEventResult _onKey(LogicalKeyboardKey key) {
    if (_validationKeys.contains(key)) {
      _open();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && widget.handleUpNavigationToSettings) {
      Actions.invoke(context, const MoveFocusToSettingsIntent());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _open() async {
    if (_pressed) return;
    setState(() => _pressed = true);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final reel = context.read<ReelService>();
    if (!reduceMotion) await Future<void>.delayed(_pressDuration);
    await reel.open();
    if (mounted) setState(() => _pressed = false);
  }
}

/// The tile's static art: a dark ground washed with the accent colour, and a
/// short stack of clip frames rising like a feed, the front one carrying a
/// play mark. Original geometry only; no logos.
class ReelTileArtPainter extends CustomPainter {
  final Color accent;
  final Color surface;

  const ReelTileArtPainter({required this.accent, required this.surface});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    final ground = Color.lerp(surface, Colors.black, 0.55)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color.lerp(ground, accent, 0.45)!, ground],
        ).createShader(rect),
    );

    // Three frames, back to front, each a little larger and lower.
    final frameHeight = size.height * 0.46;
    final frameWidth = frameHeight * 0.62;
    final baseX = size.width * 0.70;
    final baseY = size.height * 0.16;
    for (var i = 0; i < 3; i++) {
      final scale = 0.78 + i * 0.11;
      final w = frameWidth * scale;
      final h = frameHeight * scale;
      final left = baseX - w / 2 + (i - 1) * frameWidth * 0.42;
      final top = baseY + i * size.height * 0.07;
      final frame = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), Radius.circular(h * 0.12));
      final alpha = 0.22 + i * 0.26;
      canvas.drawRRect(frame, Paint()..color = Color.lerp(ground, accent, 0.25 + i * 0.2)!.withValues(alpha: alpha));
      canvas.drawRRect(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.18 + i * 0.16),
      );
      if (i == 2) {
        final c = frame.center;
        final r = h * 0.17;
        final play = Path()
          ..moveTo(c.dx - r * 0.55, c.dy - r)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx - r * 0.55, c.dy + r)
          ..close();
        canvas.drawPath(play, Paint()..color = Colors.white.withValues(alpha: 0.92));
      }
    }

    // A strip of sprocket marks down the left edge.
    final holePaint = Paint()..color = Colors.white.withValues(alpha: 0.12);
    final hole = size.height * 0.06;
    for (var y = hole; y < size.height - hole; y += hole * 2.2) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(hole * 0.8, y, hole, hole * 1.2), Radius.circular(hole * 0.25)),
        holePaint,
      );
    }
  }

  @override
  bool shouldRepaint(ReelTileArtPainter oldDelegate) => oldDelegate.accent != accent || oldDelegate.surface != surface;
}
