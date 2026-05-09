import 'package:flutter/material.dart';
import 'package:noti_notes_app/theme/contrast.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// HSV-driven custom-color picker. The user tunes hue, saturation, and
/// lightness for the surface and accent independently; the surfaceVariant
/// and onSurface slots are derived to maintain WCAG AA at body sizes.
///
/// Sliders that would push the surface or accent below body-text contrast
/// disable submit and show an inline reason — the user never escapes the
/// picker with an unreadable combination.
///
/// Returns the built [NotiThemeOverlay] via `Navigator.pop` when the user
/// taps "Apply".
class OverlayPaletteCustomPicker extends StatefulWidget {
  const OverlayPaletteCustomPicker({super.key});

  @override
  State<OverlayPaletteCustomPicker> createState() => _OverlayPaletteCustomPickerState();
}

class _OverlayPaletteCustomPickerState extends State<OverlayPaletteCustomPicker> {
  HSVColor _surface = const HSVColor.fromAHSV(1, 30, 0.18, 0.92);
  HSVColor _accent = const HSVColor.fromAHSV(1, 200, 0.40, 0.55);

  Color get _surfaceColor => _surface.toColor();
  Color get _accentColor => _accent.toColor();
  Color get _onAccentColor => clampForReadability(_accentColor);

  bool get _meetsBody => isAccessibleBody(clampForReadability(_surfaceColor), _surfaceColor);
  bool get _meetsAccent => isAccessibleBody(_onAccentColor, _accentColor);
  bool get _meetsAA => _meetsBody && _meetsAccent;

  NotiThemeOverlay _build() {
    return NotiThemeOverlay(
      surface: _surfaceColor,
      surfaceVariant: HSVColor.fromAHSV(
        1,
        _surface.hue,
        (_surface.saturation * 0.85).clamp(0.0, 1.0),
        (_surface.value * 1.05).clamp(0.0, 1.0),
      ).toColor(),
      accent: _accentColor,
      onAccent: _onAccentColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Custom palette',
              style: tokens.text.titleMd.copyWith(color: tokens.colors.onSurface),
            ),
            SizedBox(height: tokens.spacing.md),
            _PreviewCard(
              surface: _surfaceColor,
              accent: _accentColor,
              onAccent: _onAccentColor,
            ),
            SizedBox(height: tokens.spacing.lg),
            _ColorControls(
              label: 'Surface',
              color: _surface,
              onChanged: (c) => setState(() => _surface = c),
            ),
            SizedBox(height: tokens.spacing.md),
            _ColorControls(
              label: 'Accent',
              color: _accent,
              onChanged: (c) => setState(() => _accent = c),
            ),
            SizedBox(height: tokens.spacing.md),
            _ContrastBadge(
              meetsAA: _meetsAA,
              meetsBody: _meetsBody,
              meetsAccent: _meetsAccent,
            ),
            SizedBox(height: tokens.spacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                SizedBox(width: tokens.spacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _meetsAA ? () => Navigator.of(context).pop(_build()) : null,
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.surface,
    required this.accent,
    required this.onAccent,
  });

  final Color surface;
  final Color accent;
  final Color onAccent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = clampForReadability(surface);
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: tokens.shape.mdRadius,
        border: Border.all(color: tokens.colors.divider),
      ),
      padding: EdgeInsets.all(tokens.spacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(Icons.brush, color: onAccent, size: 18),
          ),
          SizedBox(width: tokens.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Sample title', style: tokens.text.titleSm.copyWith(color: fg)),
                Text('Body copy', style: tokens.text.bodySm.copyWith(color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorControls extends StatelessWidget {
  const _ColorControls({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tokens.text.labelLg.copyWith(color: tokens.colors.onSurface)),
        _NamedSlider(
          name: 'Hue',
          value: color.hue,
          min: 0,
          max: 360,
          onChanged: (v) => onChanged(color.withHue(v)),
        ),
        _NamedSlider(
          name: 'Saturation',
          value: color.saturation,
          min: 0,
          max: 1,
          onChanged: (v) => onChanged(color.withSaturation(v)),
        ),
        _NamedSlider(
          name: 'Brightness',
          value: color.value,
          min: 0,
          max: 1,
          onChanged: (v) => onChanged(color.withValue(v)),
        ),
      ],
    );
  }
}

class _NamedSlider extends StatelessWidget {
  const _NamedSlider({
    required this.name,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String name;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            name,
            style: tokens.text.labelMd.copyWith(color: tokens.colors.onSurfaceMuted),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ContrastBadge extends StatelessWidget {
  const _ContrastBadge({
    required this.meetsAA,
    required this.meetsBody,
    required this.meetsAccent,
  });

  final bool meetsAA;
  final bool meetsBody;
  final bool meetsAccent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = meetsAA ? tokens.colors.success : tokens.colors.warning;
    final label = meetsAA
        ? 'AA contrast ✓'
        : !meetsBody
            ? 'Body text contrast too low'
            : !meetsAccent
                ? 'Accent contrast too low'
                : 'Low contrast';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: tokens.shape.smRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meetsAA ? Icons.check_circle_outline : Icons.warning_amber, size: 16, color: color),
          SizedBox(width: tokens.spacing.xs),
          Text(label, style: tokens.text.labelMd.copyWith(color: color)),
        ],
      ),
    );
  }
}
