import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:noti_notes_app/features/settings/cubit/theme_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/theme_state.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

class SettingsScreen extends StatelessWidget {
  static const routeName = '/settings';
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingPrimitives.lg,
          vertical: SpacingPrimitives.md,
        ),
        children: const [
          _SectionLabel('Appearance'),
          Gap(SpacingPrimitives.sm),
          _ThemeModePicker(),
          Gap(SpacingPrimitives.xl),
          _SectionLabel('App font'),
          Gap(SpacingPrimitives.sm),
          _AppFontPicker(),
          Gap(SpacingPrimitives.xl),
          _SectionLabel('About'),
          Gap(SpacingPrimitives.sm),
          _AboutTile(),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingPrimitives.xs),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}

class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker();

  @override
  Widget build(BuildContext context) {
    final mode = context.select<ThemeCubit, ThemeMode>((c) => c.state.themeMode);
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text('System'),
          icon: Icon(Icons.brightness_auto_outlined),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text('Light'),
          icon: Icon(Icons.light_mode_outlined),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text('Dark'),
          icon: Icon(Icons.dark_mode_outlined),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (set) => context.read<ThemeCubit>().setThemeMode(set.first),
    );
  }
}

class _AppFontPicker extends StatelessWidget {
  const _AppFontPicker();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<ThemeCubit, ThemeState>(
      buildWhen: (a, b) => a.writingFont != b.writingFont,
      builder: (context, state) => Column(
        children: WritingFont.values.map((font) {
          final selected = state.writingFont == font;
          return Padding(
            padding: const EdgeInsets.only(bottom: SpacingPrimitives.sm),
            child: Material(
              color:
                  selected ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
                side: BorderSide(
                  color: selected ? scheme.primary : scheme.outline.withValues(alpha: 0.5),
                  width: 1.0,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
                onTap: () => context.read<ThemeCubit>().setWritingFont(font),
                child: Padding(
                  padding: const EdgeInsets.all(SpacingPrimitives.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              font.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Gap(SpacingPrimitives.xs),
                            Text(
                              'The quick brown fox jumps over the lazy dog',
                              style: GoogleFonts.getFont(
                                font.googleFontName,
                                fontSize: 16,
                                color: scheme.onSurface.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected) Icon(Icons.check_circle, color: scheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.5), width: 1.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingPrimitives.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NotiNotes 2.0', style: Theme.of(context).textTheme.titleMedium),
            const Gap(SpacingPrimitives.xs),
            Text(
              'A customizable, offline notes app built with Flutter.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
