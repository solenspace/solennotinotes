import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_state.dart';
import 'package:noti_notes_app/features/settings/cubit/theme_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/theme_state.dart';
import 'package:noti_notes_app/features/settings/screens/manage_ai_screen.dart';
import 'package:noti_notes_app/features/settings/widgets/ai_disclosure_sheet.dart';
import 'package:noti_notes_app/features/settings/widgets/llm_download_progress_modal.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Settings screen. The `LlmReadinessCubit` it depends on is hoisted to
/// the app shell (Spec 20 § "Hoist LlmReadinessCubit") so both this
/// screen and the editor's ✦ Assist button read the same readiness
/// state without redundant disk probes.
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
          _AiAssistSection(),
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

/// AI assist row. Hidden entirely on `AiTier.unsupported` so users on
/// devices that cannot run the on-device LLM see no UI hint that AI was
/// ever a possibility — matches the project posture for STT (Spec 15).
class _AiAssistSection extends StatelessWidget {
  const _AiAssistSection();

  @override
  Widget build(BuildContext context) {
    final canRunLlm = context.read<DeviceCapabilityService>().aiTier.canRunLlm;
    if (!canRunLlm) return const SizedBox.shrink();

    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('AI assist'),
        Gap(SpacingPrimitives.sm),
        _AiAssistTile(),
        Gap(SpacingPrimitives.xl),
      ],
    );
  }
}

class _AiAssistTile extends StatelessWidget {
  const _AiAssistTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<LlmReadinessCubit, LlmReadinessState>(
      builder: (context, state) {
        final isReady = state.phase == LlmReadinessPhase.ready;
        return Material(
          color: isReady ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
            side: BorderSide(
              color: isReady ? scheme.primary : scheme.outline.withValues(alpha: 0.5),
              width: 1.0,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
            onTap: isReady ? () => _openManageAi(context) : () => _onTap(context, state),
            child: Padding(
              padding: const EdgeInsets.all(SpacingPrimitives.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _labelFor(state),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(SpacingPrimitives.xs),
                        Text(
                          _descriptionFor(state),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.7),
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (isReady) Icon(Icons.check_circle, color: scheme.primary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Called when the row is tapped while ready — navigates to the
  /// "Manage AI" screen (Spec 20 § G) so the user can re-download or
  /// delete the model. The same screen is reachable from a long-press
  /// on the editor's ✦ Assist button.
  void _openManageAi(BuildContext context) {
    Navigator.of(context).pushNamed(ManageAiScreen.routeName);
  }

  /// Called when the row is tapped while not in `ready`. Routes by phase:
  /// idle → disclosure sheet → progress modal; failed → straight retry
  /// (the previous failure reason is already on screen via the cubit's
  /// emitted state, no need to re-confirm); downloading / verifying →
  /// re-open the progress modal so the user can find Cancel.
  Future<void> _onTap(BuildContext context, LlmReadinessState state) async {
    final cubit = context.read<LlmReadinessCubit>();
    switch (state.phase) {
      case LlmReadinessPhase.idle:
        final confirmed = await AiDisclosureSheet.show(context);
        if (confirmed != true) return;
        if (!context.mounted) return;
        await cubit.start();
        if (!context.mounted) return;
        await LlmDownloadProgressModal.show(context);
      case LlmReadinessPhase.failed:
        await cubit.start();
        if (!context.mounted) return;
        await LlmDownloadProgressModal.show(context);
      case LlmReadinessPhase.downloading:
      case LlmReadinessPhase.verifying:
        await LlmDownloadProgressModal.show(context);
      case LlmReadinessPhase.ready:
        // Ready rows are non-tappable (InkWell.onTap == null).
        break;
    }
  }

  static String _labelFor(LlmReadinessState state) {
    return switch (state.phase) {
      LlmReadinessPhase.idle => 'Enable AI assist (around 640 MB)',
      LlmReadinessPhase.downloading => state.totalBytes > 0
          ? 'Downloading… ${(state.progressFraction * 100).round()}%'
          : 'Downloading…',
      LlmReadinessPhase.verifying => 'Verifying…',
      LlmReadinessPhase.ready => 'AI assist enabled',
      LlmReadinessPhase.failed => 'Download failed — retry',
    };
  }

  static String _descriptionFor(LlmReadinessState state) {
    return switch (state.phase) {
      LlmReadinessPhase.idle => 'On-device language model. Downloaded once, kept on this device.',
      LlmReadinessPhase.downloading || LlmReadinessPhase.verifying => 'One-time, one-way download.',
      LlmReadinessPhase.ready => 'Model on this device. No network calls during AI use.',
      LlmReadinessPhase.failed => state.failureReason ?? 'The previous attempt did not finish.',
    };
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
