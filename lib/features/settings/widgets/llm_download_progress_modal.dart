import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import '../../../theme/tokens.dart';
import '../cubit/llm_readiness_cubit.dart';
import '../cubit/llm_readiness_state.dart';

/// Full-screen modal that drives the LLM model download. Stays in front of
/// settings until the cubit reaches `ready` (auto-dismiss) or the user
/// cancels (manual dismiss after the cubit returns the state to `idle`).
///
/// Wraps the live progress region in `Semantics(liveRegion: true)` so
/// VoiceOver / TalkBack announce percentage updates without re-reading the
/// surrounding chrome — the accessibility floor in `context/ui-context.md`
/// mandates this for any animated progress UI.
class LlmDownloadProgressModal extends StatelessWidget {
  const LlmDownloadProgressModal({super.key});

  /// Shows the modal over [context]. Returns when the modal is dismissed
  /// (either auto on `ready` or manually on cancel). The provided cubit is
  /// re-injected via `BlocProvider.value` so the modal sees the same
  /// instance the settings row owns.
  static Future<void> show(BuildContext context) {
    final cubit = context.read<LlmReadinessCubit>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => BlocProvider<LlmReadinessCubit>.value(
        value: cubit,
        child: const LlmDownloadProgressModal(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LlmReadinessCubit, LlmReadinessState>(
      listenWhen: (prev, curr) => prev.phase != curr.phase,
      listener: (context, state) {
        if (state.phase == LlmReadinessPhase.ready || state.phase == LlmReadinessPhase.idle) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        final tokens = context.tokens;
        return Dialog.fullscreen(
          backgroundColor: tokens.colors.surface,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(state: state),
                  const Spacer(),
                  _ProgressBlock(state: state),
                  const Spacer(),
                  _CancelButton(state: state),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final LlmReadinessState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _titleFor(state.phase),
          style: tokens.text.titleLg.copyWith(color: tokens.colors.onSurface),
        ),
        Gap(tokens.spacing.xs),
        Text(
          'Downloading once. Nothing else leaves your device.',
          style: tokens.text.bodySm.copyWith(color: tokens.colors.onSurfaceMuted),
        ),
      ],
    );
  }

  static String _titleFor(LlmReadinessPhase phase) {
    return switch (phase) {
      LlmReadinessPhase.idle || LlmReadinessPhase.downloading => 'Downloading AI model',
      LlmReadinessPhase.verifying => 'Verifying download',
      LlmReadinessPhase.ready => 'AI assist enabled',
      LlmReadinessPhase.failed => 'Download failed',
    };
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.state});

  final LlmReadinessState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fraction = state.progressFraction;
    final percent = (fraction * 100).round();
    final isVerifying = state.phase == LlmReadinessPhase.verifying;
    final isFailed = state.phase == LlmReadinessPhase.failed;

    return Semantics(
      container: true,
      liveRegion: true,
      label: switch (state.phase) {
        LlmReadinessPhase.downloading => 'Downloading AI model: $percent percent',
        LlmReadinessPhase.verifying => 'Verifying AI model download',
        LlmReadinessPhase.failed => 'Download failed: ${state.failureReason ?? 'unknown error'}',
        _ => '',
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: tokens.shape.smRadius,
            child: LinearProgressIndicator(
              minHeight: 6,
              value: isVerifying ? null : fraction,
              backgroundColor: tokens.colors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                isFailed ? tokens.colors.error : tokens.colors.accent,
              ),
            ),
          ),
          Gap(tokens.spacing.sm),
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isVerifying
                      ? 'Verifying…'
                      : '${_formatBytes(state.progressBytes)} / '
                          '${_formatBytes(state.totalBytes)}',
                  style: tokens.text.bodySm.copyWith(
                    color: tokens.colors.onSurfaceMuted,
                  ),
                ),
                if (!isVerifying)
                  Text(
                    '$percent%',
                    style: tokens.text.bodySm.copyWith(
                      color: tokens.colors.onSurfaceMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (isFailed) ...[
            Gap(tokens.spacing.md),
            Text(
              state.failureReason ?? 'Unknown error.',
              style: tokens.text.bodyMd.copyWith(color: tokens.colors.error),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const mib = 1024 * 1024;
    final mb = bytes / mib;
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.state});

  final LlmReadinessState state;

  @override
  Widget build(BuildContext context) {
    final isFailed = state.phase == LlmReadinessPhase.failed;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => context.read<LlmReadinessCubit>().cancel(),
            child: Text(isFailed ? 'Close' : 'Cancel download'),
          ),
        ),
        if (isFailed) ...[
          const Gap(12),
          Expanded(
            child: FilledButton(
              onPressed: () => context.read<LlmReadinessCubit>().start(),
              child: const Text('Retry'),
            ),
          ),
        ],
      ],
    );
  }
}
