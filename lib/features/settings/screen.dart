import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:noti_notes_app/features/inbox/screen.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_state.dart';
import 'package:noti_notes_app/features/settings/cubit/theme_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/theme_state.dart';
import 'package:noti_notes_app/features/settings/cubit/whisper_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/whisper_readiness_state.dart';
import 'package:noti_notes_app/features/settings/screens/manage_ai_screen.dart';
import 'package:noti_notes_app/features/settings/widgets/ai_disclosure_sheet.dart';
import 'package:noti_notes_app/features/settings/widgets/llm_download_progress_modal.dart';
import 'package:noti_notes_app/features/settings/widgets/whisper_disclosure_sheet.dart';
import 'package:noti_notes_app/features/settings/widgets/whisper_download_progress_modal.dart';
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
      appBar: AppBar(title: Text(context.l10n.settings_title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingPrimitives.lg,
          vertical: SpacingPrimitives.md,
        ),
        children: [
          _SectionLabel(context.l10n.settings_appearance),
          const Gap(SpacingPrimitives.sm),
          const _ThemeModePicker(),
          const Gap(SpacingPrimitives.xl),
          _SectionLabel(context.l10n.settings_app_font),
          const Gap(SpacingPrimitives.sm),
          const _AppFontPicker(),
          const Gap(SpacingPrimitives.xl),
          const _AiAssistSection(),
          _SectionLabel(context.l10n.settings_sharing),
          const Gap(SpacingPrimitives.sm),
          const _InboxTile(),
          const Gap(SpacingPrimitives.xl),
          _SectionLabel(context.l10n.settings_about),
          const Gap(SpacingPrimitives.sm),
          const _AboutTile(),
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
      segments: [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text(context.l10n.theme_system),
          icon: const Icon(Icons.brightness_auto_outlined),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text(context.l10n.theme_light),
          icon: const Icon(Icons.light_mode_outlined),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text(context.l10n.theme_dark),
          icon: const Icon(Icons.dark_mode_outlined),
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
                              context.l10n.settings_font_specimen,
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

/// AI assist + voice transcription rows. Each tile hides itself when
/// the device is unsupported for that capability (LLM and Whisper can
/// be enabled independently per Spec 21 § G — both gates live on the
/// same `AiTier` in v1, but the section keeps them as siblings so a
/// future divergence doesn't require restructuring this widget).
class _AiAssistSection extends StatelessWidget {
  const _AiAssistSection();

  @override
  Widget build(BuildContext context) {
    final tier = context.read<DeviceCapabilityService>().aiTier;
    if (!tier.canRunLlm && !tier.canRunWhisper) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(context.l10n.settings_ai_section),
        const Gap(SpacingPrimitives.sm),
        if (tier.canRunLlm) ...[
          const _AiAssistTile(),
          const Gap(SpacingPrimitives.sm),
        ],
        if (tier.canRunWhisper) const _VoiceTranscriptionTile(),
        const Gap(SpacingPrimitives.xl),
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
                          _labelFor(context, state),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(SpacingPrimitives.xs),
                        Text(
                          _descriptionFor(context, state),
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

  static String _labelFor(BuildContext context, LlmReadinessState state) {
    return switch (state.phase) {
      LlmReadinessPhase.idle => context.l10n.ai_settings_enable_label,
      LlmReadinessPhase.downloading => state.totalBytes > 0
          ? context.l10n.ai_settings_downloading_progress((state.progressFraction * 100).round())
          : context.l10n.ai_settings_downloading,
      LlmReadinessPhase.verifying => context.l10n.ai_settings_verifying,
      LlmReadinessPhase.ready => context.l10n.ai_settings_enabled,
      LlmReadinessPhase.failed => context.l10n.ai_settings_failed_retry,
    };
  }

  static String _descriptionFor(BuildContext context, LlmReadinessState state) {
    return switch (state.phase) {
      LlmReadinessPhase.idle => context.l10n.ai_settings_description_idle,
      LlmReadinessPhase.downloading ||
      LlmReadinessPhase.verifying =>
        context.l10n.ai_settings_description_downloading,
      LlmReadinessPhase.ready => context.l10n.ai_settings_description_ready,
      LlmReadinessPhase.failed =>
        state.failureReason ?? context.l10n.ai_settings_description_failed,
    };
  }
}

/// Spec 21 — second AI tile, mirrors [_AiAssistTile] for the on-device
/// Whisper model. Independent of LLM (`canRunWhisper` and the readiness
/// cubit are separate gates).
class _VoiceTranscriptionTile extends StatelessWidget {
  const _VoiceTranscriptionTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<WhisperReadinessCubit, WhisperReadinessState>(
      builder: (context, state) {
        final isReady = state.phase == WhisperReadinessPhase.ready;
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
                          _labelFor(context, state),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(SpacingPrimitives.xs),
                        Text(
                          _descriptionFor(context, state),
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

  void _openManageAi(BuildContext context) {
    Navigator.of(context).pushNamed(ManageAiScreen.routeName);
  }

  Future<void> _onTap(BuildContext context, WhisperReadinessState state) async {
    final cubit = context.read<WhisperReadinessCubit>();
    switch (state.phase) {
      case WhisperReadinessPhase.idle:
        final mb = (cubit.spec.totalBytes / (1024 * 1024)).round();
        final confirmed = await WhisperDisclosureSheet.show(
          context,
          approxMegabytes: mb,
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        await cubit.start();
        if (!context.mounted) return;
        await WhisperDownloadProgressModal.show(context);
      case WhisperReadinessPhase.failed:
        await cubit.start();
        if (!context.mounted) return;
        await WhisperDownloadProgressModal.show(context);
      case WhisperReadinessPhase.downloading:
      case WhisperReadinessPhase.verifying:
        await WhisperDownloadProgressModal.show(context);
      case WhisperReadinessPhase.ready:
        // Ready rows are non-tappable here (InkWell.onTap routes to
        // ManageAi instead).
        break;
    }
  }

  static String _labelFor(BuildContext context, WhisperReadinessState state) {
    final mb = (context.read<WhisperReadinessCubit>().spec.totalBytes / (1024 * 1024)).round();
    return switch (state.phase) {
      WhisperReadinessPhase.idle => context.l10n.whisper_settings_enable_label(mb),
      WhisperReadinessPhase.downloading => state.totalBytes > 0
          ? context.l10n
              .whisper_settings_downloading_progress((state.progressFraction * 100).round())
          : context.l10n.whisper_settings_downloading,
      WhisperReadinessPhase.verifying => context.l10n.whisper_settings_verifying,
      WhisperReadinessPhase.ready => context.l10n.whisper_settings_enabled,
      WhisperReadinessPhase.failed => context.l10n.whisper_settings_failed_retry,
    };
  }

  static String _descriptionFor(BuildContext context, WhisperReadinessState state) {
    return switch (state.phase) {
      WhisperReadinessPhase.idle => context.l10n.whisper_settings_description_idle,
      WhisperReadinessPhase.downloading ||
      WhisperReadinessPhase.verifying =>
        context.l10n.whisper_settings_description_downloading,
      WhisperReadinessPhase.ready => context.l10n.whisper_settings_description_ready,
      WhisperReadinessPhase.failed =>
        state.failureReason ?? context.l10n.whisper_settings_description_failed,
    };
  }
}

/// Spec 25 — opens the receiver-side inbox. The "Receive a shared note"
/// toggle lives inside the inbox screen itself; this tile is a plain
/// navigation row so Settings stays a destination index rather than a
/// place where transport lifecycle hides.
class _InboxTile extends StatelessWidget {
  const _InboxTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.5), width: 1.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        onTap: () => Navigator.of(context).pushNamed(InboxScreen.routeName),
        child: Padding(
          padding: const EdgeInsets.all(SpacingPrimitives.lg),
          child: Row(
            children: [
              Icon(Icons.inbox_outlined, color: scheme.onSurface),
              const Gap(SpacingPrimitives.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.settings_receive_shared,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Gap(SpacingPrimitives.xs),
                    Text(
                      context.l10n.settings_receive_description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
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
            Text(context.l10n.about_app_name, style: Theme.of(context).textTheme.titleMedium),
            const Gap(SpacingPrimitives.xs),
            Text(
              context.l10n.about_description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
