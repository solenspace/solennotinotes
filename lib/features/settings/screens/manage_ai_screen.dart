import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_state.dart';
import 'package:noti_notes_app/features/settings/widgets/llm_download_progress_modal.dart';
import 'package:noti_notes_app/services/ai/llm_model_constants.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Manage AI')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingPrimitives.lg,
          vertical: SpacingPrimitives.md,
        ),
        children: const [
          _ModelInfoCard(),
          Gap(SpacingPrimitives.lg),
          _ReDownloadTile(),
          Gap(SpacingPrimitives.sm),
          _DeleteTile(),
        ],
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
                  'Model',
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
                _InfoRow(label: 'Size', value: '$sizeMb MB'),
                const _InfoRow(label: 'Schema', value: LlmModelConstants.version),
                _InfoRow(label: 'Status', value: _statusText(state)),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _statusText(LlmReadinessState state) => switch (state.phase) {
        LlmReadinessPhase.idle => 'Not on this device',
        LlmReadinessPhase.downloading => 'Downloading…',
        LlmReadinessPhase.verifying => 'Verifying…',
        LlmReadinessPhase.ready => 'On this device, verified',
        LlmReadinessPhase.failed => 'Last attempt failed',
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
      label: 'Re-download model',
      description: 'Replace the file on this device with a fresh copy.',
      icon: Icons.refresh_rounded,
      color: scheme.primary,
      onTap: () async {
        final confirmed = await _confirm(
          context,
          title: 'Re-download model?',
          body: 'This downloads about 640 MB. The current model file is '
              'replaced when the new one is verified.',
          confirmLabel: 'Re-download',
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
      label: 'Delete model and disable AI',
      description: 'Frees about 640 MB. AI affordances disappear until you '
          'opt back in from Settings.',
      icon: Icons.delete_outline_rounded,
      color: scheme.error,
      onTap: () async {
        final confirmed = await _confirm(
          context,
          title: 'Delete model?',
          body: 'AI assist will be turned off. You can re-enable it later, '
              'but the model will need to be downloaded again.',
          confirmLabel: 'Delete',
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
            child: const Text('Cancel'),
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
