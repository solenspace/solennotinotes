import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import '../../../theme/tokens.dart';
import '../cubit/whisper_readiness_cubit.dart';
import '../cubit/whisper_readiness_state.dart';

/// Full-screen modal that drives the Whisper model download (Spec 21).
/// Mirrors [`LlmDownloadProgressModal`](llm_download_progress_modal.dart);
/// kept as a sibling rather than generalised because the cubit type +
/// state enum differ. A future refactor could extract a shared base
/// once a third on-device model lands.
class WhisperDownloadProgressModal extends StatelessWidget {
  const WhisperDownloadProgressModal({super.key});

  /// Shows the modal over [context]. Returns when the modal is
  /// dismissed (auto on `ready` / `idle`, or manually on cancel). The
  /// hoisted [WhisperReadinessCubit] is re-injected via
  /// `BlocProvider.value` so the modal sees the same instance the
  /// settings tile owns.
  static Future<void> show(BuildContext context) {
    final cubit = context.read<WhisperReadinessCubit>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => BlocProvider<WhisperReadinessCubit>.value(
        value: cubit,
        child: const WhisperDownloadProgressModal(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WhisperReadinessCubit, WhisperReadinessState>(
      listenWhen: (prev, curr) => prev.phase != curr.phase,
      listener: (context, state) {
        if (state.phase == WhisperReadinessPhase.ready ||
            state.phase == WhisperReadinessPhase.idle) {
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

  final WhisperReadinessState state;

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
          'Downloading once. Audio never leaves your device.',
          style: tokens.text.bodySm.copyWith(color: tokens.colors.onSurfaceMuted),
        ),
      ],
    );
  }

  static String _titleFor(WhisperReadinessPhase phase) {
    return switch (phase) {
      WhisperReadinessPhase.idle ||
      WhisperReadinessPhase.downloading =>
        'Downloading transcription model',
      WhisperReadinessPhase.verifying => 'Verifying download',
      WhisperReadinessPhase.ready => 'Voice transcription enabled',
      WhisperReadinessPhase.failed => 'Download failed',
    };
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.state});

  final WhisperReadinessState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fraction = state.progressFraction;
    final percent = (fraction * 100).round();
    final isVerifying = state.phase == WhisperReadinessPhase.verifying;
    final isFailed = state.phase == WhisperReadinessPhase.failed;

    return Semantics(
      container: true,
      liveRegion: true,
      label: switch (state.phase) {
        WhisperReadinessPhase.downloading => 'Downloading transcription model: $percent percent',
        WhisperReadinessPhase.verifying => 'Verifying transcription model download',
        WhisperReadinessPhase.failed =>
          'Download failed: ${state.failureReason ?? 'unknown error'}',
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

  final WhisperReadinessState state;

  @override
  Widget build(BuildContext context) {
    final isFailed = state.phase == WhisperReadinessPhase.failed;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => context.read<WhisperReadinessCubit>().cancel(),
            child: Text(isFailed ? 'Close' : 'Cancel download'),
          ),
        ),
        if (isFailed) ...[
          const Gap(12),
          Expanded(
            child: FilledButton(
              onPressed: () => context.read<WhisperReadinessCubit>().start(),
              child: const Text('Retry'),
            ),
          ),
        ],
      ],
    );
  }
}
