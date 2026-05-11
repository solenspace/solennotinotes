import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import 'package:noti_notes_app/features/note_editor/cubit/transcription_cubit.dart';
import 'package:noti_notes_app/features/note_editor/cubit/transcription_state.dart';
import 'package:noti_notes_app/l10n/build_context_l10n.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Outcome the editor screen reacts to when [TranscriptionOverlay]
/// closes. The overlay stays presentational — it never mutates
/// `note.blocks` itself; the screen owns the block-list state and the
/// `BlocksReplaced` / `AudioBlockRemoved` dispatches (mirrors the
/// audio-capture flow established in Spec 13).
enum TranscriptionAcceptance {
  /// User cancelled mid-progress, hit Discard on a ready result, or
  /// closed the overlay without picking an accept path. No-op for the
  /// screen.
  discard,

  /// User chose "Insert below". The screen inserts a new text block
  /// after the source audio block.
  insertBelow,

  /// User chose "Replace audio". The screen substitutes the audio
  /// block with the new text block and dispatches `AudioBlockRemoved`
  /// so the file is cleaned up.
  replaceAudio,
}

/// Result returned by [TranscriptionOverlay.show]. `kind` is always
/// non-null; `transcript` is non-null only when `kind` is an
/// accept-path (`insertBelow` / `replaceAudio`).
class TranscriptionAcceptanceResult {
  const TranscriptionAcceptanceResult.discard()
      : kind = TranscriptionAcceptance.discard,
        transcript = null;
  const TranscriptionAcceptanceResult.insertBelow(this.transcript)
      : kind = TranscriptionAcceptance.insertBelow;
  const TranscriptionAcceptanceResult.replaceAudio(this.transcript)
      : kind = TranscriptionAcceptance.replaceAudio;

  final TranscriptionAcceptance kind;
  final String? transcript;
}

/// Spec 21 transcription overlay. Three modes driven by
/// [TranscriptionCubit]:
///
///   1. **running** — determinate `LinearProgressIndicator` bound to
///      `state.progress`; Cancel button. The progress label is wrapped
///      in `Semantics(liveRegion: true, label: ...)` so VoiceOver /
///      TalkBack announce changes.
///   2. **ready** — selectable `SelectableText` of the trimmed result;
///      three buttons: Insert below / Replace audio / Discard.
///   3. **failed** — error message + Try again / Discard.
///
/// The overlay owns the [TranscriptionCubit] (via internal
/// [BlocProvider.create]) so the cubit's lifetime equals the bottom
/// sheet's. On dismiss without an accept path the cubit cancels
/// in-flight work via its `close()` lifecycle.
class TranscriptionOverlay extends StatelessWidget {
  const TranscriptionOverlay({
    super.key,
    required this.audioFilePath,
    required this.cubitFactory,
  });

  final String audioFilePath;

  /// Factory for the per-overlay cubit. Wrapped this way (rather than
  /// passing a constructed cubit) so the bottom sheet's
  /// `BlocProvider.create` owns disposal — the cubit is closed when
  /// the sheet pops, regardless of how it was dismissed.
  final TranscriptionCubit Function() cubitFactory;

  /// Opens the overlay and returns the user's acceptance choice. The
  /// caller is responsible for translating the choice into block-list
  /// mutations (see `lib/features/note_editor/screen.dart`).
  static Future<TranscriptionAcceptanceResult> show(
    BuildContext context, {
    required String audioFilePath,
    required TranscriptionCubit Function() cubitFactory,
  }) async {
    final tokens = context.tokens;
    final result = await showModalBottomSheet<TranscriptionAcceptanceResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: tokens.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.shape.lg),
        ),
      ),
      builder: (_) => TranscriptionOverlay(
        audioFilePath: audioFilePath,
        cubitFactory: cubitFactory,
      ),
    );
    return result ?? const TranscriptionAcceptanceResult.discard();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TranscriptionCubit>(
      create: (_) => cubitFactory()..start(audioFilePath),
      child: _TranscriptionOverlayBody(audioFilePath: audioFilePath),
    );
  }
}

class _TranscriptionOverlayBody extends StatelessWidget {
  const _TranscriptionOverlayBody({required this.audioFilePath});

  final String audioFilePath;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          const _DragHandle(),
          const _PrivacyBanner(),
          Expanded(
            child: BlocBuilder<TranscriptionCubit, TranscriptionState>(
              builder: (context, state) {
                switch (state.phase) {
                  case TranscriptionPhase.idle:
                  case TranscriptionPhase.running:
                    return _RunningBody(scrollController: scroll, state: state);
                  case TranscriptionPhase.ready:
                    return _ReadyBody(scrollController: scroll, state: state);
                  case TranscriptionPhase.failed:
                    return _FailedBody(
                      scrollController: scroll,
                      state: state,
                      audioFilePath: audioFilePath,
                    );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: tokens.colors.divider,
        borderRadius: tokens.shape.pillRadius,
      ),
    );
  }
}

/// Mirrors the AI assist sheet's privacy banner — same posture, same
/// reassurance. "Running on this device — nothing leaves it."
class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.sm,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(tokens.shape.sm),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: scheme.primary),
            Gap(tokens.spacing.sm),
            Expanded(
              child: Text(
                context.l10n.transcription_privacy_banner,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.85),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningBody extends StatelessWidget {
  const _RunningBody({required this.scrollController, required this.state});

  final ScrollController scrollController;
  final TranscriptionState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final percent = (state.progress * 100).round();
    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.transcription_progress_title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Gap(tokens.spacing.xs),
          Text(
            context.l10n.transcription_progress_body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
          Gap(tokens.spacing.lg),
          // Determinate progress bar — Whisper reports a coarse fraction
          // per processed segment. liveRegion announces percent to AT.
          Semantics(
            liveRegion: true,
            label: context.l10n.transcription_progress_semantic(percent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.shape.sm),
                  child: LinearProgressIndicator(
                    value: state.progress,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
                Gap(tokens.spacing.xs),
                Text(
                  context.l10n.percent_value(percent),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
          Gap(tokens.spacing.xl),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                // Pop first, then cancel: popping the sheet triggers
                // BlocProvider.dispose → cubit.close(), which already
                // cancels the in-flight subscription. Doing it the other
                // way around requires an `await` between cancel() and
                // pop, and the BlocBuilder rebuild that lands in
                // between can deactivate the local `context`.
                Navigator.of(context).pop(
                  const TranscriptionAcceptanceResult.discard(),
                );
                unawaited(context.read<TranscriptionCubit>().cancel());
              },
              icon: const Icon(Icons.close_rounded),
              label: Text(context.l10n.common_cancel),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.scrollController, required this.state});

  final ScrollController scrollController;
  final TranscriptionState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.transcription_ready_title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Gap(tokens.spacing.sm),
          Container(
            padding: EdgeInsets.all(tokens.spacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(tokens.shape.sm),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
            ),
            child: SelectableText(
              state.result.isEmpty ? '(empty transcript)' : state.result,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Gap(tokens.spacing.lg),
          // Three accept paths laid out as full-width tiles for an
          // unambiguous tap target on small screens. Order: positive
          // (Insert) → destructive (Replace) → escape (Discard).
          Semantics(
            button: true,
            label: context.l10n.transcription_insert_below_label,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                TranscriptionAcceptanceResult.insertBelow(state.result),
              ),
              icon: const Icon(Icons.subdirectory_arrow_right_rounded),
              label: Text(context.l10n.transcription_insert_below),
            ),
          ),
          Gap(tokens.spacing.sm),
          Semantics(
            button: true,
            label: context.l10n.transcription_replace_audio_label,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(
                TranscriptionAcceptanceResult.replaceAudio(state.result),
              ),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: Text(context.l10n.transcription_replace_audio),
            ),
          ),
          Gap(tokens.spacing.sm),
          Semantics(
            button: true,
            label: context.l10n.transcription_discard_label,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(
                const TranscriptionAcceptanceResult.discard(),
              ),
              icon: const Icon(Icons.close_rounded),
              label: Text(context.l10n.common_discard),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedBody extends StatelessWidget {
  const _FailedBody({
    required this.scrollController,
    required this.state,
    required this.audioFilePath,
  });

  final ScrollController scrollController;
  final TranscriptionState state;
  final String audioFilePath;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: scheme.error),
              Gap(tokens.spacing.sm),
              Text(
                context.l10n.transcription_failed_title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          Gap(tokens.spacing.sm),
          Text(
            state.errorMessage ??
                'The on-device runtime could not transcribe '
                    'this clip. Try again, or discard.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.85),
                ),
          ),
          Gap(tokens.spacing.lg),
          FilledButton.icon(
            onPressed: () async {
              // Re-arm the same cubit; it lazy-loads the runtime if
              // needed and re-subscribes. Keep the overlay open so the
              // user sees progress on the retry attempt.
              await context.read<TranscriptionCubit>().cancel();
              if (!context.mounted) return;
              await context.read<TranscriptionCubit>().start(audioFilePath);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.transcription_try_again),
          ),
          Gap(tokens.spacing.sm),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(
              const TranscriptionAcceptanceResult.discard(),
            ),
            icon: const Icon(Icons.close_rounded),
            label: Text(context.l10n.common_discard),
          ),
        ],
      ),
    );
  }
}
