import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_state.dart';
import 'package:noti_notes_app/features/settings/cubit/whisper_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/whisper_readiness_state.dart';
import 'package:noti_notes_app/features/settings/widgets/llm_download_progress_modal.dart';
import 'package:noti_notes_app/features/settings/widgets/whisper_download_progress_modal.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/services/ai/llm_model_constants.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// "Manage AI" surface (Spec 20 § G). Lists the on-device model's
/// identity (filename + size + verification hash) and exposes the two
/// lifecycle controls Spec 20 calls out:
///
///   * **Re-download model** — useful if the user suspects the file is
///     corrupted or wants to refresh after a model update.
///   * **Delete model and disable AI** — frees ~640 MB and turns off
///     every AI affordance until the user opts back in.
///
/// Reachable from (a) the editor's long-press on the ✦ Assist button
/// and (b) the Settings screen's AI assist tile when the model is
/// already on disk. Both entry points read the hoisted
/// [LlmReadinessCubit] — there is no per-route cubit here.
class ManageAiScreen extends StatelessWidget {
  static const routeName = '/settings/manage-ai';
  const ManageAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tier = context.read<DeviceCapabilityService>().aiTier;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.manage_ai_title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingPrimitives.lg,
          vertical: SpacingPrimitives.md,
        ),
        children: [
          if (tier.canRunLlm) ...[
            _SectionLabel(context.l10n.manage_ai_section_assist),
            const Gap(SpacingPrimitives.sm),
            const _ModelInfoCard(),
            const Gap(SpacingPrimitives.sm),
            const _ReDownloadTile(),
            const Gap(SpacingPrimitives.sm),
            const _DeleteTile(),
            const Gap(SpacingPrimitives.xl),
          ],
          if (tier.canRunWhisper) ...[
            _SectionLabel(context.l10n.manage_ai_section_voice),
            const Gap(SpacingPrimitives.sm),
            const _WhisperModelInfoCard(),
            const Gap(SpacingPrimitives.sm),
            const _WhisperReDownloadTile(),
            const Gap(SpacingPrimitives.sm),
            const _WhisperDeleteTile(),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
}

/// Read-only card with the frozen identity of the model file.
class _ModelInfoCard extends StatelessWidget {
  const _ModelInfoCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sizeMb = (LlmModelConstants.totalBytes / (1024 * 1024)).round();
    return BlocBuilder<LlmReadinessCubit, LlmReadinessState>(
      builder: (context, state) {
        return Material(
          color: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
            side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(SpacingPrimitives.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.manage_ai_model_label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const Gap(SpacingPrimitives.xs),
                Text(
                  LlmModelConstants.filename,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Gap(SpacingPrimitives.md),
                _InfoRow(
                  label: context.l10n.manage_ai_size_label,
                  value: context.l10n.manage_ai_size_value(sizeMb),
                ),
                _InfoRow(
                  label: context.l10n.manage_ai_schema_label,
                  value: LlmModelConstants.version,
                ),
                _InfoRow(
                  label: context.l10n.manage_ai_status_label,
                  value: _statusText(context, state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _statusText(BuildContext context, LlmReadinessState state) => switch (state.phase) {
        LlmReadinessPhase.idle => context.l10n.manage_ai_status_not_installed,
        LlmReadinessPhase.downloading => context.l10n.manage_ai_status_downloading,
        LlmReadinessPhase.verifying => context.l10n.manage_ai_status_verifying,
        LlmReadinessPhase.ready => context.l10n.manage_ai_status_ready,
        LlmReadinessPhase.failed => context.l10n.manage_ai_status_failed,
      };
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingPrimitives.xs),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReDownloadTile extends StatelessWidget {
  const _ReDownloadTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ActionTile(
      label: context.l10n.manage_ai_redownload_label,
      description: 'Replace the file on this device with a fresh copy.',
      icon: Icons.refresh_rounded,
      color: scheme.primary,
      onTap: () async {
        final confirmed = await _confirm(
          context,
          title: context.l10n.manage_ai_redownload_confirm_title,
          body: context.l10n.manage_ai_redownload_confirm_body,
          confirmLabel: context.l10n.manage_ai_redownload_label,
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        final cubit = context.read<LlmReadinessCubit>();
        await cubit.disable();
        if (!context.mounted) return;
        await cubit.start();
        if (!context.mounted) return;
        await LlmDownloadProgressModal.show(context);
      },
    );
  }
}

class _DeleteTile extends StatelessWidget {
  const _DeleteTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ActionTile(
      label: context.l10n.manage_ai_delete_label,
      description: 'Frees about 640 MB. AI affordances disappear until you '
          'opt back in from Settings.',
      icon: Icons.delete_outline_rounded,
      color: scheme.error,
      onTap: () async {
        final confirmed = await _confirm(
          context,
          title: context.l10n.manage_ai_delete_confirm_title,
          body: context.l10n.manage_ai_delete_confirm_body,
          confirmLabel: context.l10n.manage_ai_delete_label,
          isDestructive: true,
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        await context.read<LlmReadinessCubit>().disable();
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(SpacingPrimitives.lg),
          child: Row(
            children: [
              Icon(icon, color: color),
              const Gap(SpacingPrimitives.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
                    ),
                    const Gap(SpacingPrimitives.xs),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool isDestructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(color: isDestructive ? scheme.error : null),
            ),
          ),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Spec 21 — Whisper section (mirrors LLM section above one-for-one).
// ---------------------------------------------------------------------------

class _WhisperModelInfoCard extends StatelessWidget {
  const _WhisperModelInfoCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<WhisperReadinessCubit, WhisperReadinessState>(
      builder: (context, state) {
        final spec = context.read<WhisperReadinessCubit>().spec;
        final sizeMb = (spec.totalBytes / (1024 * 1024)).round();
        return Material(
          color: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RadiusPrimitives.sm),
            side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(SpacingPrimitives.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.manage_ai_model_label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const Gap(SpacingPrimitives.xs),
                Text(
                  spec.filename,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Gap(SpacingPrimitives.md),
                _InfoRow(
                  label: context.l10n.manage_ai_size_label,
                  value: context.l10n.manage_ai_size_value(sizeMb),
                ),
                _InfoRow(
                  label: context.l10n.manage_ai_schema_label,
                  value: spec.version,
                ),
                _InfoRow(
                  label: context.l10n.manage_ai_status_label,
                  value: _statusText(context, state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _statusText(BuildContext context, WhisperReadinessState state) =>
      switch (state.phase) {
        WhisperReadinessPhase.idle => context.l10n.manage_ai_status_not_installed,
        WhisperReadinessPhase.downloading => context.l10n.manage_ai_status_downloading,
        WhisperReadinessPhase.verifying => context.l10n.manage_ai_status_verifying,
        WhisperReadinessPhase.ready => context.l10n.manage_ai_status_ready,
        WhisperReadinessPhase.failed => context.l10n.manage_ai_status_failed,
      };
}

class _WhisperReDownloadTile extends StatelessWidget {
  const _WhisperReDownloadTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ActionTile(
      label: context.l10n.manage_whisper_redownload_label,
      description: 'Replace the transcription model on this device with a fresh copy.',
      icon: Icons.refresh_rounded,
      color: scheme.primary,
      onTap: () async {
        final spec = context.read<WhisperReadinessCubit>().spec;
        final mb = (spec.totalBytes / (1024 * 1024)).round();
        final confirmed = await _confirm(
          context,
          title: context.l10n.manage_whisper_redownload_confirm_title,
          body: context.l10n.manage_whisper_redownload_confirm_body(mb),
          confirmLabel: context.l10n.manage_whisper_redownload_label,
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        final cubit = context.read<WhisperReadinessCubit>();
        await cubit.disable();
        if (!context.mounted) return;
        await cubit.start();
        if (!context.mounted) return;
        await WhisperDownloadProgressModal.show(context);
      },
    );
  }
}

class _WhisperDeleteTile extends StatelessWidget {
  const _WhisperDeleteTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ActionTile(
      label: context.l10n.manage_whisper_delete_label,
      description: 'Frees the on-device model. The audio files in your '
          'notes are untouched. You can re-enable later.',
      icon: Icons.delete_outline_rounded,
      color: scheme.error,
      onTap: () async {
        final confirmed = await _confirm(
          context,
          title: context.l10n.manage_whisper_delete_confirm_title,
          body: context.l10n.manage_whisper_delete_confirm_body,
          confirmLabel: context.l10n.manage_whisper_delete_label,
          isDestructive: true,
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        await context.read<WhisperReadinessCubit>().disable();
      },
    );
  }
}
